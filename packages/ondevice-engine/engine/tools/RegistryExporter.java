import io.magicmobile.core.Json;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.lang.reflect.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.stream.*;

/** BUILD-TIME JVM tool. Reflection here is NOT linked into the iOS runtime. */
public final class RegistryExporter {
    record CardEntry(String binary,String source,boolean withInfo,boolean noInfo) {}
    private static final List<String> NO_REFLECTION=List.of("mage.sets.","mage.db.","mage.game.result.");
    public static void main(String[] args) throws Exception {
        if(args.length<2)throw new IllegalArgumentException("Usage: RegistryExporter OUTPUT CLASSES_DIR...");
        Path output=Path.of(args[0]);Files.createDirectories(output);
        Path source=output.resolve("java/io/magicmobile/generated");Files.createDirectories(source);
        // Clean stale generated classes' SOURCE only, never user files or the upstream checkout.
        try(Stream<Path> paths=Files.list(source)){for(Path p:paths.toList())if(p.getFileName().toString().matches("Generated.*\\.java"))Files.delete(p);}
        TreeSet<String> names=new TreeSet<>();
        for(int i=1;i<args.length;i++){
            Path dir=Path.of(args[i]);
            try(Stream<Path> paths=Files.walk(dir)){
                paths.filter(p->p.toString().endsWith(".class")).forEach(p->{
                    String n=dir.relativize(p).toString().replace(File.separatorChar,'.');n=n.substring(0,n.length()-6);
                    if(n.startsWith("mage."))names.add(n);
                });
            }
        }
        if(names.isEmpty())throw new IllegalArgumentException("No XMage classes found");
        Class<?> cardType=Class.forName("mage.cards.Card"), infoType=Class.forName("mage.cards.CardSetInfo"), setType=Class.forName("mage.cards.ExpansionSet");
        List<CardEntry> cards=new ArrayList<>();List<Class<?>> sets=new ArrayList<>();List<Object> excluded=new ArrayList<>(),reflection=new ArrayList<>();
        for(String name:names){
            // Missing dependencies are fatal: never silently ship a partial factory inventory.
            Class<?> c=Class.forName(name,false,RegistryExporter.class.getClassLoader());
            // Never created reflectively on mobile, and registering them keeps their code: set and booster collator
            // classes (sets come from the set catalogue), the H2 entity manager and the protobuf results.
            if(!c.isInterface() && c.getCanonicalName()!=null && NO_REFLECTION.stream().noneMatch(name::startsWith))
                reflection.add(Json.map("name",name,"allDeclaredFields",true,"allDeclaredConstructors",true));
            if(!Modifier.isPublic(c.getModifiers()) || Modifier.isAbstract(c.getModifiers()) || c.getCanonicalName()==null)continue;
            if(cardType.isAssignableFrom(c)){
                boolean with=constructor(c,UUID.class,infoType),without=constructor(c,UUID.class);
                if(with||without)cards.add(new CardEntry(c.getName(),c.getCanonicalName(),with,without));
                else excluded.add(Json.map("class",name,"reason","No public UUID/CardSetInfo or UUID constructor; direct-new-only until reviewed"));
            }
            if(setType.isAssignableFrom(c)){
                Method m=c.getMethod("getInstance");
                if(!Modifier.isStatic(m.getModifiers()))throw new IllegalStateException("Set singleton method is not static: "+name);
                sets.add(c);
            }
        }
        Set<String> registered=cards.stream().map(CardEntry::binary).collect(Collectors.toSet());
        if(cards.isEmpty() || sets.isEmpty())throw new IllegalStateException("Empty card or set registry");
        String inventory=cards.toString()+sets.stream().map(Class::getName).toList();
        String hash=HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(inventory.getBytes(StandardCharsets.UTF_8)));
        String pre="package io.magicmobile.generated;\nimport mage.cards.Card;\nimport mage.cards.CardSetInfo;\n";
        StringBuilder dispatch=new StringBuilder(pre+"public final class GeneratedCardFactory {\n public static final String CATALOGUE_HASH=\""+hash+"\";\n public static Card create(String name,CardSetInfo info) {\n  switch(Math.floorMod(name.hashCode(),256)) {\n");
        for(int bucket=0;bucket<256;bucket++){
            final int index=bucket;List<CardEntry> entries=cards.stream().filter(c->Math.floorMod(c.binary().hashCode(),256)==index).toList();
            if(entries.isEmpty())continue;
            String classname="GeneratedCardBucket"+bucket;
            dispatch.append("   case ").append(bucket).append(": return ").append(classname).append(".create(name,info);\n");
            // A sorted name table and an int switch: each case is one allocation and one constructor call. A
            // switch on the name string compiled a hash dispatch, an inlined String.equals and its own throw
            // site per card, about 20 MB of the native engine's code for 32k cards.
            List<CardEntry> sorted=entries.stream().sorted(Comparator.comparing(CardEntry::binary)).toList();
            StringBuilder b=new StringBuilder(pre+"final class "+classname+" {\n private static final String[] NAMES={\n");
            StringBuilder requires=new StringBuilder();
            for(CardEntry e:sorted){ b.append("  \"").append(e.binary()).append("\",\n");requires.append(e.withInfo()&&!e.noInfo()?'1':'0'); }
            b.append(" };\n /** '1' where the card has only a CardSetInfo constructor. */\n private static final String REQUIRES_INFO=\"").append(requires).append("\";\n");
            b.append(" static Card create(String name,CardSetInfo info) {\n  int index=java.util.Arrays.binarySearch(NAMES,name);\n");
            b.append("  if(index<0)throw new IllegalArgumentException(\"Unregistered card class: \"+name);\n");
            b.append("  if(info==null && REQUIRES_INFO.charAt(index)=='1')throw new IllegalArgumentException(\"CardSetInfo required\");\n  switch(index) {\n");
            for(int i=0;i<sorted.size();i++){
                CardEntry e=sorted.get(i);
                b.append("   case ").append(i).append(": ");
                if(e.withInfo()&&e.noInfo())b.append("return info==null ? new ").append(e.source()).append("(null) : new ").append(e.source()).append("(null,info);");
                else if(e.withInfo())b.append("return new ").append(e.source()).append("(null,info);");
                else b.append("return new ").append(e.source()).append("(null);");
                b.append('\n');
            }
            b.append("   default: throw new IllegalStateException(\"Card table out of step: \"+name);\n  }\n }\n}\n");Files.writeString(source.resolve(classname+".java"),b);
        }
        dispatch.append("   default: throw new IllegalArgumentException(\"Unregistered card class: \"+name);\n  }\n }\n}\n");
        Files.writeString(source.resolve("GeneratedCardFactory.java"),dispatch);
        // Sets come from the bundled set catalogue (written below), in this order, so Sets (a HashMap) iterates them
        // as it iterated the set classes. Only the classes with their own booster code stay referenced, for packs.
        List<Class<?>> custom=sets.stream().filter(RegistryExporter::customBooster).toList();
        Files.writeString(source.resolve("GeneratedSetRegistry.java"),"package io.magicmobile.generated;\n"
            +"public final class GeneratedSetRegistry { public static synchronized void install() {\n"
            +" if(mage.cards.Sets.getInstance().size()=="+sets.size()+")return;\n"
            +" if(!mage.cards.Sets.getInstance().isEmpty())throw new IllegalStateException("+Json.write("Partial set registry; restart the engine")+");\n"
            +" java.util.List<mage.cards.MobileExpansionSet> sets=mage.cards.MobileExpansionSet.load(GeneratedCardFactory.CATALOGUE_HASH,GeneratedBoosterSets::create);\n"
            +" if(sets.size()!="+sets.size()+")throw new IllegalStateException("+Json.write("Set catalogue does not match the card registry")+");\n"
            +" for(mage.cards.MobileExpansionSet set:sets)mage.cards.Sets.getInstance().addSet(set);\n}}\n");
        StringBuilder boosters=new StringBuilder("package io.magicmobile.generated;\n/** Set classes that override booster generation (Booster Tutor); created on first use. */\n"
            +"final class GeneratedBoosterSets { static mage.cards.ExpansionSet create(String code) {\n  switch(code) {\n");
        // The cast through Object is checked at run time, so the JVM verifier does not load every listed class.
        for(Class<?> c:custom)
            boosters.append("   case ").append(Json.write(setValue(c,"code"))).append(": return (mage.cards.ExpansionSet)(Object)")
                .append(c.getCanonicalName()).append(".getInstance();\n");
        boosters.append("   default: return null;\n  }\n }\n}\n");
        Files.writeString(source.resolve("GeneratedBoosterSets.java"),boosters);
        // Output JSONL printings from real set metadata. Decks need not trust caller-supplied card class/name/rarity.
        try(BufferedWriter w=Files.newBufferedWriter(output.resolve("catalogue.jsonl"))){
            for(Class<?> set:sets){
                Object instance=set.getMethod("getInstance").invoke(null);
                String code=(String)setType.getMethod("getCode").invoke(instance);
                for(Object info:(List<?>)setType.getMethod("getSetCardInfo").invoke(instance)){
                    Class<?> t=info.getClass();
                    String printingClass=((Class<?>)t.getMethod("getCardClass").invoke(info)).getName();
                    if(!registered.contains(printingClass))
                        throw new IllegalStateException("Printing references an unregistered constructor: "+code+" / "+printingClass);
                    w.write(Json.write(Json.map("name",t.getMethod("getName").invoke(info),"setCode",code,
                        "collectorNumber",t.getMethod("getCardNumber").invoke(info),"rarity",((Enum<?>)t.getMethod("getRarity").invoke(info)).name(),
                        "className",((Class<?>)t.getMethod("getCardClass").invoke(info)).getName())));w.newLine();
                }
            }
        }
        writeSetCatalogue(output,hash,sets,custom);
        // Large catalogues can exceed wire JSON limits. Stream build metadata, entry by entry.
        try(BufferedWriter w=Files.newBufferedWriter(output.resolve("reflect-config.json"))) {
            w.write("[");boolean first=true;
            for(Object entry:reflection){if(!first)w.write(",\n");first=false;w.write(Json.write(entry));}
            w.write("]\n");
        }
        Files.writeString(output.resolve("registry-report.json"),Json.write(Json.map("cardClasses",cards.size(),"setClasses",sets.size(),"registryHash",hash,
            "hashScope","constructor signatures and set class names; combine with upstream and adapter revision","excluded",excluded)));
        System.out.println("Generated "+cards.size()+" card factories and "+sets.size()+" set references; exclusions="+excluded.size());
    }
    private static boolean constructor(Class<?> c,Class<?>... args){try{c.getConstructor(args);return true;}catch(NoSuchMethodException e){return false;}}

    /** MobileExpansionSet.FIELDS: ExpansionSet's fields that a set class's constructor sets, then customBooster. */
    private static final List<String> SET_FIELDS=List.of("code","name","releaseDate","setType","blockName","parentSet",
        "hasBasicLands","rotationSet","hasBoosters","numBoosterSpecial","numBoosterLands","ratioBoosterSpecialLand",
        "ratioBoosterSpecialLandNumerator","ratioBoosterSpecialCommon","ratioBoosterSpecialRare","ratioBoosterSpecialMythic",
        "numBoosterCommon","numBoosterUncommon","numBoosterRare","numBoosterDoubleFaced","ratioBoosterMythic",
        "hasUnbalancedColors","hasOnlyMulticolorCards","hasAlternateBoosterPrintings","maxCardNumberInBooster","customBooster");
    /** ExpansionSet's other fields: the card list (exported as printings) and booster caches (empty until a pack is made). */
    private static final Set<String> SET_STATE=Set.of("cards","savedCards","savedSpecialCards","savedReprints","inBoosterMap");

    /**
     * True when booster generation in this set class differs from ExpansionSet's: it (or a superclass below
     * ExpansionSet) declares an instance method that is not private, or an instance field. Its packs are then
     * made by the class itself; every other set's packs depend only on the exported fields and the catalogue.
     */
    private static boolean customBooster(Class<?> set) {
        try {
            Class<?> base=Class.forName("mage.cards.ExpansionSet");
            for(Class<?> c=set;c!=base;c=c.getSuperclass()) {
                for(Method m:c.getDeclaredMethods())
                    if(!Modifier.isStatic(m.getModifiers()) && !Modifier.isPrivate(m.getModifiers()) && !m.isSynthetic()) return true;
                for(Field f:c.getDeclaredFields()) if(!Modifier.isStatic(f.getModifiers())) return true;
            }
            return false;
        } catch(ClassNotFoundException e) { throw new IllegalStateException(e); }
    }
    private static Object setValue(Class<?> set,String field) {
        try {
            Field f=Class.forName("mage.cards.ExpansionSet").getDeclaredField(field);f.setAccessible(true);
            return f.get(set.getMethod("getInstance").invoke(null));
        } catch(ReflectiveOperationException e) { throw new IllegalStateException(set.getName()+"."+field,e); }
    }
    /** A catalogue column: "-" is null, so no text may be "-" or hold a tab or line break. */
    private static String text(Object value) {
        if(value==null)return "-";
        String s=value.toString();
        if(s.equals("-") || s.contains("\t") || s.contains("\n") || s.contains("\r"))throw new IllegalStateException("Unencodable catalogue text: "+s);
        return s;
    }
    private static String column(Class<?> set,String field) throws Exception {
        Object value=setValue(set,field);
        if(value instanceof Boolean)return (Boolean)value?"1":"0";
        if(value instanceof Double) {
            String s=Double.toString((Double)value);
            if(Double.doubleToRawLongBits(Double.parseDouble(s))!=Double.doubleToRawLongBits((Double)value))throw new IllegalStateException("Double "+s);
            return s;
        }
        if(value instanceof Date) {
            // Set classes call ExpansionSet.buildDate(y,m,d) in the device's time zone; so does MobileExpansionSet.
            Calendar day=Calendar.getInstance();day.setTime((Date)value);
            int y=day.get(Calendar.YEAR),m=day.get(Calendar.MONTH)+1,d=day.get(Calendar.DAY_OF_MONTH);
            Object rebuilt=Class.forName("mage.cards.ExpansionSet").getMethod("buildDate",int.class,int.class,int.class).invoke(null,y,m,d);
            if(!value.equals(rebuilt))throw new IllegalStateException("Release date is not a buildDate day: "+set.getName());
            return y+"-"+m+"-"+d;
        }
        if(value!=null && Class.forName("mage.cards.ExpansionSet").isInstance(value))return text(setValue(value.getClass(),"code"));
        if(value instanceof Enum<?>)return ((Enum<?>)value).name();
        if(value!=null && !(value instanceof String) && !(value instanceof Integer))throw new IllegalStateException("Unexported set field type: "+field);
        return text(value);
    }

    /**
     * mage/mobile/set-catalogue.tsv.gz: a header line, the distinct card graphic infos (G), one row per set class
     * in registry order with its field values (S), then every SetCardInfo of every set in list order (P).
     */
    private static void writeSetCatalogue(Path output,String hash,List<Class<?>> sets,List<Class<?>> custom) throws Exception {
        Class<?> setType=Class.forName("mage.cards.ExpansionSet");
        Set<String> declared=new TreeSet<>();
        for(Field f:setType.getDeclaredFields())if(!Modifier.isStatic(f.getModifiers()))declared.add(f.getName());
        Set<String> expected=new TreeSet<>(SET_STATE);expected.addAll(SET_FIELDS.subList(0,SET_FIELDS.size()-1));
        if(!declared.equals(expected))throw new IllegalStateException("Review ExpansionSet's fields for the set catalogue: "+declared);
        Set<String> graphicFields=new TreeSet<>();
        for(Field f:Class.forName("mage.cards.CardGraphicInfo").getDeclaredFields())if(!Modifier.isStatic(f.getModifiers()))graphicFields.add(f.getName());
        if(!graphicFields.equals(Set.of("frameColor","frameStyle","useVariousArt")))throw new IllegalStateException("Review CardGraphicInfo: "+graphicFields);
        Map<String,Integer> graphics=new LinkedHashMap<>();
        List<String> setRows=new ArrayList<>(),printingRows=new ArrayList<>();
        for(Class<?> set:sets) {
            for(String state:List.of("savedCards","savedSpecialCards","inBoosterMap"))
                if(!((Map<?,?>)setValue(set,state)).isEmpty())throw new IllegalStateException("Booster cache filled at export: "+set.getName());
            if(setValue(set,"savedReprints")!=null)throw new IllegalStateException("Booster cache filled at export: "+set.getName());
            StringBuilder row=new StringBuilder("S\t").append(text(set.getName()));
            for(String field:SET_FIELDS)row.append('\t').append(field.equals("customBooster")?(custom.contains(set)?"1":"0"):column(set,field));
            setRows.add(row.toString());
            String code=text(setValue(set,"code"));
            for(Object info:(List<?>)setValue(set,"cards")) {
                Class<?> t=info.getClass();
                Object graphic=t.getMethod("getGraphicInfo").invoke(info);
                int index=0;
                if(graphic!=null) {
                    Class<?> g=graphic.getClass();
                    Object color=g.getMethod("getFrameColor").invoke(graphic),style=g.getMethod("getFrameStyle").invoke(graphic);
                    if(color!=null && !color.equals(color.getClass().getConstructor(String.class).newInstance(color.toString())))
                        throw new IllegalStateException("Frame color does not round-trip: "+color);
                    String key=text(style==null?null:((Enum<?>)style).name())+"\t"+((Boolean)g.getMethod("getUsesVariousArt").invoke(graphic)?"1":"0")
                        +"\t"+(color==null?"-":color.toString());
                    index=graphics.computeIfAbsent(key,k->graphics.size()+1);
                }
                printingRows.add(String.join("\t","P",code,text(t.getMethod("getCardNumber").invoke(info)),text(t.getMethod("getName").invoke(info)),
                    ((Enum<?>)t.getMethod("getRarity").invoke(info)).name(),((Class<?>)t.getMethod("getCardClass").invoke(info)).getName(),
                    Integer.toString(index)));
            }
        }
        if(graphics.size()>Byte.MAX_VALUE)throw new IllegalStateException("Too many graphic infos for the catalogue index");
        Path resources=output.resolve("resources/mage/mobile");Files.createDirectories(resources);
        Path file=resources.resolve("set-catalogue.tsv.gz");
        // GZIPOutputStream writes no timestamp, so the same sets give the same bytes.
        try(Writer w=new OutputStreamWriter(new java.util.zip.GZIPOutputStream(Files.newOutputStream(file)),StandardCharsets.UTF_8)) {
            w.write(String.join("\t","magicmobile-set-catalogue","1",hash,Integer.toString(sets.size()),
                Integer.toString(printingRows.size()),Integer.toString(graphics.size()))+"\n");
            for(Map.Entry<String,Integer> g:graphics.entrySet())w.write("G\t"+g.getValue()+"\t"+g.getKey()+"\n");
            for(String row:setRows)w.write(row+"\n");
            for(String row:printingRows)w.write(row+"\n");
        }
        String digest=HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(file)));
        Files.writeString(output.resolve("set-catalogue-report.json"),Json.write(Json.map("sets",sets.size(),"printings",printingRows.size(),
            "graphicInfos",graphics.size(),"registryHash",hash,"resource","mage/mobile/set-catalogue.tsv.gz","sha256",digest,
            "customBoosterSets",custom.stream().map(c->c.getName()).toList()))+"\n");
    }
}
