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
            if(!c.isInterface() && c.getCanonicalName()!=null)
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
            StringBuilder b=new StringBuilder(pre+"final class "+classname+" { static Card create(String name,CardSetInfo info) { switch(name) {\n");
            for(CardEntry e:entries){
                b.append(" case \"").append(e.binary()).append("\": ");
                if(e.withInfo()&&e.noInfo())b.append("return info==null ? new ").append(e.source()).append("(null) : new ").append(e.source()).append("(null,info);");
                else if(e.withInfo())b.append("if(info==null)throw new IllegalArgumentException(\"CardSetInfo required\"); return new ").append(e.source()).append("(null,info);");
                else b.append("return new ").append(e.source()).append("(null);");
                b.append('\n');
            }
            b.append(" default: throw new IllegalArgumentException(\"Unregistered card class: \"+name); } } }\n");Files.writeString(source.resolve(classname+".java"),b);
        }
        dispatch.append("   default: throw new IllegalArgumentException(\"Unregistered card class: \"+name);\n  }\n }\n}\n");
        Files.writeString(source.resolve("GeneratedCardFactory.java"),dispatch);
        StringBuilder sr=new StringBuilder("package io.magicmobile.generated;\npublic final class GeneratedSetRegistry { public static synchronized void install() {\n if(mage.cards.Sets.getInstance().size()=="+sets.size()+")return;\n if(!mage.cards.Sets.getInstance().isEmpty())throw new IllegalStateException("+Json.write("Partial set registry; restart the engine")+");\n");
        for(int start=0;start<sets.size();start+=64){
            String cname="GeneratedSetBucket"+(start/64);sr.append(cname).append(".install();\n");
            StringBuilder b=new StringBuilder("package io.magicmobile.generated;\nfinal class "+cname+" {static void install(){\n");
            for(Class<?> c:sets.subList(start,Math.min(start+64,sets.size())))b.append("mage.cards.Sets.getInstance().addSet(").append(c.getCanonicalName()).append(".getInstance());\n");
            b.append("}}\n");Files.writeString(source.resolve(cname+".java"),b);
        }
        sr.append("}}\n");Files.writeString(source.resolve("GeneratedSetRegistry.java"),sr);
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
}
