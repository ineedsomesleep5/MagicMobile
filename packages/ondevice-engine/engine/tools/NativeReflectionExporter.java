import io.magicmobile.core.Json;
import java.io.Serializable;
import java.lang.reflect.*;
import java.nio.file.*;
import java.util.*;
import java.util.stream.*;

/**
 * Build-time native metadata. Never changes the full static card factory inventory.
 *
 * NativeReflectionExporter OUTPUT_DIR CLASSES_DIR... [--serialization EXTRA_CLASSES_DIR...]
 *
 * reflect-config.json: targeted reflection for the CLASSES_DIRs (unchanged scope).
 * serialization-config.json: every Serializable class of the CLASSES_DIRs and EXTRA dirs in the
 * packages save/resume checkpoints accept, plus the JDK types io.magicmobile.xmage.Checkpoints
 * allows, and every other class a checkpoint stream can name (superclasses, arrays, Class
 * objects), so a native image can write and read any game state (docs/PROTOCOL.md,
 * docs/NATIVE_METADATA.md).
 */
public final class NativeReflectionExporter {
    private static final Map<String,Map<String,Object>> entries=new TreeMap<>();
    private static final Set<Type> seenTypes=new HashSet<>();
    private static final Set<String> dtoTypes=new TreeSet<>();
    private static final String[] CHECKPOINT_PACKAGES={"mage.","io.magicmobile.xmage."};
    /**
     * Classes allowed to keep a serializable lambda ($deserializeLambda$), each with the reviewed
     * reason its lambda can never reach a checkpoint. Empty: every such upstream lambda is a named
     * class (scripts/prepare_upstream.py). Listed classes are still NOT lambdaCapturingTypes (that
     * breaks the pinned GraalVM 22.1 build), and the checkpoint writer refuses SerializedLambda.
     */
    private static final Map<String,String> LAMBDA_SAFE=Map.of();
    /**
     * Bounds of the Class-typed serial fields that upstream declares raw or as Class<?>, from the
     * values upstream assigns them (reviewed at 4825513). An unreviewed one fails the export.
     */
    private static final Map<String,String> CLASS_FIELD_BOUNDS=Map.of(
        // Set as EquipAbility.class, LoyaltyAbility.class or MeditateAbility.class; matched with isAssignableFrom.
        "mage.abilities.effects.common.continuous.ActivateAbilitiesAnyTimeYouCouldCastInstantEffect.activatedAbility","mage.abilities.Ability",
        // Each set's card classes (set metadata, not game state).
        "mage.cards.ExpansionSet$SetCardInfo.cardClass","mage.cards.Card");

    public static void main(String[] args) throws Exception {
        List<String> arguments=new ArrayList<>(Arrays.asList(args));
        List<String> extra=new ArrayList<>();
        int split=arguments.indexOf("--serialization");
        if(split>=0) { extra.addAll(arguments.subList(split+1,arguments.size()));arguments=arguments.subList(0,split); }
        if(arguments.size()<2) throw new IllegalArgumentException("OUTPUT_DIR CLASSES_DIR... [--serialization CLASSES_DIR...]");
        Set<String> names=new TreeSet<>();
        for(String root:arguments.subList(1,arguments.size())) names.addAll(classNames(Path.of(root),"mage."));
        ClassLoader loader=NativeReflectionExporter.class.getClassLoader();
        Class<?> watcher=Class.forName("mage.watchers.Watcher",false,loader);
        Class<?> cardView=Class.forName("mage.view.CardView",false,loader);
        Class<?> commandView=Class.forName("mage.view.CommandObjectView",false,loader);
        Class<?> token=Class.forName("mage.game.permanent.token.Token",false,loader);
        Class<?> plane=Class.forName("mage.game.command.Plane",false,loader);
        Class<?> emblem=Class.forName("mage.game.command.Emblem",false,loader);
        int watchers=0,dynamicObjects=0,cardClasses=0;
        Class<?> card=Class.forName("mage.cards.Card",false,loader);
        for(String name:names) {
            // Linkage failures must remain fatal; no missing-class filtering.
            Class<?> type=Class.forName(name,false,loader);
            if(card.isAssignableFrom(type))cardClasses++;
            if(watcher.isAssignableFrom(type)) {
                watchers++;
                for(Class<?> c=type;c!=null && c.getName().startsWith("mage.");c=c.getSuperclass())
                    entry(c).put("allDeclaredFields",true);
                if(!Modifier.isAbstract(type.getModifiers()))entry(type).put("allDeclaredConstructors",true);
            }
            if(!type.isInterface() && !Modifier.isAbstract(type.getModifiers())
                    && (token.isAssignableFrom(type)||plane.isAssignableFrom(type)||emblem.isAssignableFrom(type))) {
                dynamicObjects++;entry(type).put("allDeclaredConstructors",true);
            }
            // Include runtime DTO subclasses as well as their declared generic field graph.
            if(cardView.isAssignableFrom(type)||commandView.isAssignableFrom(type))visit(type);
        }
        for(String root:List.of("mage.view.GameView","mage.view.AbilityPickerView"))
            visit(Class.forName(root,false,loader));
        // Bundled immutable metadata is decoded and defensively copied, never exposed as game state.
        Class<?> metadata=Class.forName("mage.cards.repository.CardInfo",false,loader);
        visit(metadata);entry(metadata).put("methods",List.of(Json.map("name","<init>","parameterTypes",List.of())));
        if(entries.containsKey("mage.remote.SessionImpl") || entries.containsKey("mage.game.GameState"))
            throw new IllegalStateException("Client DTO graph unexpectedly roots server/private engine state");
        if(cardClasses<30000 || watchers==0 || dynamicObjects==0)
            throw new IllegalStateException("Expected the full pinned upstream inventory");
        Path output=Path.of(args[0]);Files.createDirectories(output);
        Files.writeString(output.resolve("reflect-config.json"),Json.write(new ArrayList<>(entries.values()))+"\n");
        // Without --serialization (diagnostic probes) no serialization metadata is produced.
        Map<String,Object> serialization=split<0?null:serialization(arguments.subList(1,arguments.size()),extra,loader,output);
        Map<String,Object> report=Json.map("scope","experimental-reflection-metadata-not-native-compatibility-proof",
            "inventoryClasses",names.size(),"cardTypesInspected",cardClasses,"watcherTypes",watchers,
            "dynamicTokenPlaneEmblemTypes",dynamicObjects,"dtoTypes",new ArrayList<>(dtoTypes),
            "reflectionEntries",entries.size(),"staticCardRegistryChanged",false,
            "serverSessionRooted",false,"serialization",serialization,"limitations",List.of("Runtime native tests still required",
                "Serialization metadata covers checkpoint classes; external-library metadata remains a separate gate"));
        Files.writeString(output.resolve("report.json"),Json.write(report)+"\n");
        System.out.println(Json.write(report));
    }

    /**
     * Save/resume streams may hold any Serializable engine, card, ability, effect, watcher, filter,
     * target or token class, so every one is registered (not only those one game used). The JDK
     * list is the checkpoint allowlist itself. Proxies and serializable lambdas are refused by the
     * checkpoint writer, so none are registered.
     *
     * A native image resolves every class descriptor of a stream through Class.forName, which only
     * knows registered classes; a JVM never fails that way. So the list is closed over what a stream
     * can name: the Serializable superclasses of every listed class (superclass descriptors); array
     * types (see below) with every nested array type, including the serial fields of the JDK types
     * and their serialization proxies (EnumSet$SerializationProxy.elements is an Enum[]; BitSet
     * persists a long[]); and the classes Class-typed serial fields can hold. The JDK proxies and
     * readResolve results themselves (EnumSet$SerializationProxy, CollSer, RegularEnumSet,
     * ImmutableCollections$ListN, ...) are on the allowlist. RealCheckpointTests records every
     * class that real checkpoint streams write and read, and fails if one is not listed here.
     *
     * No lambdaCapturingTypes: GraalVM 22.1 parses every method of such a class and fails the build
     * ("Serializable lambda class must contain the writeReplace method") at the first lambda that is
     * not serializable. So any registered class that still declares $deserializeLambda$ (a
     * serializable lambda or method reference, e.g. after an upstream bump) fails this export and
     * must become a named class in prepare_upstream.py. The pinned parser requires both keys of the
     * object form, so "lambdaCapturingTypes" is written as an empty list.
     */
    private static Map<String,Object> serialization(List<String> roots,List<String> extra,ClassLoader loader,Path output) throws Exception {
        Set<String> names=new TreeSet<>();
        for(String root:roots) for(String prefix:CHECKPOINT_PACKAGES) names.addAll(classNames(Path.of(root),prefix));
        for(String root:extra) for(String prefix:CHECKPOINT_PACKAGES) names.addAll(classNames(Path.of(root),prefix));
        Class<?> checkpoints=Class.forName("io.magicmobile.xmage.Checkpoints",false,loader);
        Method jdk=checkpoints.getDeclaredMethod("jdkTypes");
        jdk.setAccessible(true);
        Method allowed=checkpoints.getDeclaredMethod("allowed",Class.class);
        allowed.setAccessible(true);
        @SuppressWarnings("unchecked") Set<String> allowlist=new TreeSet<>((Set<String>)jdk.invoke(null));
        Set<String> jdkTypes=new TreeSet<>(allowlist);
        Map<String,Class<?>> types=new TreeMap<>();
        int concrete=0,withoutUid=0,members=0;Set<String> lambdaHosts=new TreeSet<>(),desktop=new TreeSet<>();
        // Mage.Common's Swing client components (MageCard, MageTable, ...) are Serializable but never
        // part of a headless game. Registering them would pull AWT/X11 into the native image.
        Class<?> component=Class.forName("java.awt.Component",false,loader);
        for(String name:names) {
            Class<?> type=Class.forName(name,false,loader);
            Method[] methods=type.getDeclaredMethods();
            for(Method method:methods) if(method.getName().equals("$deserializeLambda$") && !LAMBDA_SAFE.containsKey(name)) lambdaHosts.add(name);
            if(type.isInterface() || type.isSynthetic() || !Serializable.class.isAssignableFrom(type)) continue;
            if(component.isAssignableFrom(type)) { desktop.add(name);continue; }
            types.put(name,type);
            if(!Modifier.isAbstract(type.getModifiers())) concrete++;
            boolean uid=false;
            for(Field field:type.getDeclaredFields()) {
                if(field.getName().equals("serialVersionUID") && Modifier.isStatic(field.getModifiers())) uid=true;
                members++;
            }
            members+=type.getDeclaredConstructors().length+methods.length;
            if(!uid) withoutUid++;
        }
        for(String name:new ArrayList<>(jdkTypes)) {
            Class<?> type=Class.forName(name,false,loader); // A missing JDK type must fail the build.
            // Object[] and Map.Entry[] are only pre-checked by JDK collections; they never have stream classes.
            if(type==Object.class || type.isInterface()) { jdkTypes.remove(name);continue; }
            if(!Serializable.class.isAssignableFrom(type)) throw new IllegalStateException("Not serializable: "+name);
        }
        if(!lambdaHosts.isEmpty())
            throw new IllegalStateException("Classes with serializable lambdas (not allowed in checkpoints or GraalVM 22.1 "
                +"lambdaCapturingTypes); replace each with a named class in scripts/prepare_upstream.py: "+lambdaHosts);
        int engineClasses=types.size();
        for(String name:jdkTypes) types.put(name,Class.forName(name,false,loader));
        // Superclass descriptors. CheckpointSerializationFeature registers these too; listing them
        // makes this file the complete set of stream classes that RealCheckpointTests checks.
        Set<String> superclasses=new TreeSet<>();
        for(Class<?> type:new ArrayList<>(types.values()))
            for(Class<?> parent=type.getSuperclass();parent!=null && Serializable.class.isAssignableFrom(parent);parent=parent.getSuperclass())
                if(types.putIfAbsent(parent.getName(),parent)==null) superclasses.add(parent.getName());
        // Array descriptors, each with its nested array types, where the checkpoint allowlist admits
        // them (the writer refuses the others) and no desktop UI class is the element type:
        // - the array types of every listed class's serial fields;
        // - every array type engine code creates (anewarray, multianewarray and newarray in the
        //   scanned class files). Streams hold arrays that no field declares: Predicates.and(a,b)
        //   keeps the Predicate[] of Arrays.asList's generic varargs in an Arrays$ArrayList;
        // - arrays of each allowlisted JDK type, which JDK code creates too (String.split).
        Set<String> candidates=new TreeSet<>();
        Map<Class<?>,Set<String>> classBounds=new LinkedHashMap<>(); // bound -> Class-typed serial fields
        for(Class<?> type:types.values())
            for(Map.Entry<String,Type> field:serialFieldTypes(type).entrySet()) {
                Class<?> raw=erasure(field.getValue());
                if(raw.isArray()) candidates.add(raw.getName());
                // Class<? extends Ability> holds a class literal within that bound; Class<?> any.
                String holder=type.getName()+"."+field.getKey();
                if(raw==Class.class) classBounds.computeIfAbsent(CLASS_FIELD_BOUNDS.containsKey(holder)
                    ?Class.forName(CLASS_FIELD_BOUNDS.get(holder),false,loader):field.getValue() instanceof ParameterizedType
                    ?erasure(((ParameterizedType)field.getValue()).getActualTypeArguments()[0]):Object.class,
                    bound->new TreeSet<>()).add(holder);
            }
        int fieldArrays=candidates.size();
        List<Path> scanned=new ArrayList<>();
        for(String root:roots) scanned.add(Path.of(root));
        for(String root:extra) scanned.add(Path.of(root));
        Set<String> created=new TreeSet<>(),literals=new TreeSet<>();
        scanEngineCode(scanned,created,literals);
        candidates.addAll(created);
        for(String name:allowlist) candidates.add("[L"+name+";");
        Map<String,Class<?>> arrays=new TreeMap<>();
        for(String name:candidates) {
            Class<?> array=admitted(name,allowlist,allowed,component,loader);
            for(;array!=null && array.isArray();array=array.getComponentType()) arrays.put(array.getName(),array);
        }
        for(String name:List.of("[Ljava.lang.Enum;","[Ljava.lang.Object;","[Ljava.util.concurrent.ConcurrentHashMap$Segment;","[J","[B",
                "[Lmage.filter.predicate.Predicate;","[Lmage.constants.CardType;"))
            if(!arrays.containsKey(name)) throw new IllegalStateException("Missing checkpoint array type "+name);
        // Class objects: a stream names the class a Class-typed serial field holds. Upstream assigns
        // class literals to them (AbilityPredicate(FlyingAbility.class), CardImpl's meld classes,
        // EnumMap's key type), so every class literal in engine code within a field's bound is
        // listed. Serializable ones already are; any other (an interface, say) is listed so that
        // Class.forName resolves it (CheckpointSerializationFeature registers nothing else for it).
        Set<String> classObjects=new TreeSet<>();
        for(String name:literals) {
            Class<?> literal=admitted(name,allowlist,allowed,component,loader);
            if(literal==null || types.containsKey(name) || arrays.containsKey(name)) continue;
            for(Class<?> bound:classBounds.keySet()) if(bound.isAssignableFrom(literal)) { classObjects.add(name);break; }
        }
        if(classBounds.containsKey(Object.class))
            throw new IllegalStateException("Serial fields of type Class<?> could hold any class; bound them or list their values: "
                +classBounds.get(Object.class));
        List<Object> registered=new ArrayList<>();
        for(String name:types.keySet()) registered.add(Json.map("name",name));
        for(String name:arrays.keySet()) registered.add(Json.map("name",name));
        for(String name:classObjects) registered.add(Json.map("name",name));
        Files.writeString(output.resolve("serialization-config.json"),
            Json.write(Json.map("types",registered,"lambdaCapturingTypes",List.of()))+"\n");
        if(concrete<30000 || !types.containsKey("io.magicmobile.xmage.Checkpoints$Payload")
                || !types.containsKey("io.magicmobile.xmage.MobileHumanPlayer") || !types.containsKey("mage.player.ai.ComputerPlayer7")
                || !types.containsKey("mage.abilities.keyword.ReconfigureUnattachAbility$AttachedToCreatureCondition"))
            throw new IllegalStateException("Serialization inventory is missing checkpoint classes; pass the plugin and engine class directories");
        return Json.map("entries",registered.size(),"engineClasses",engineClasses,"concreteEngineClasses",concrete,
            "jdkTypes",jdkTypes.size(),"serializableSuperclasses",new ArrayList<>(superclasses),
            "arrayTypes",arrays.size(),"serialFieldArrayTypes",fieldArrays,"arrayTypesCreatedByEngineCode",created.size(),
            "classFieldBounds",classBounds.entrySet().stream().collect(Collectors.toMap(e->e.getKey().getName(),
                e->new ArrayList<>(e.getValue()),(a,b)->a,TreeMap::new)),
            "nonSerializableClassObjects",new ArrayList<>(classObjects),"classesWithoutSerialVersionUID",withoutUid,
            "declaredMembersOfRegisteredEngineClasses",members,"lambdaCapturingTypes",List.of(),
            "reviewedLambdaSafe",new ArrayList<>(LAMBDA_SAFE.keySet()),"excludedDesktopUiClasses",new ArrayList<>(desktop),"proxies",0);
    }
    /**
     * The types of the fields a stream writes for this class. JDK classes, and any class declaring
     * serialPersistentFields: ObjectStreamClass itself (BitSet persists a long[] it has no field
     * for; String persists none of its fields). Others: the non-static, non-transient declared
     * fields, read without initializing the class (ObjectStreamClass would run every card's static
     * initializer).
     */
    private static Map<String,Type> serialFieldTypes(Class<?> type) {
        Map<String,Type> result=new LinkedHashMap<>();
        if(Enum.class.isAssignableFrom(type)) return result; // an enum constant is written as its name
        Map<String,Field> declared=new HashMap<>();
        boolean persistent=false;
        for(Field field:type.getDeclaredFields()) {
            persistent|=field.getName().equals("serialPersistentFields") && Modifier.isStatic(field.getModifiers());
            declared.put(field.getName(),field);
        }
        if(persistent || type.getName().startsWith("java.")) {
            java.io.ObjectStreamClass stream=java.io.ObjectStreamClass.lookup(type);
            if(stream!=null) for(java.io.ObjectStreamField field:stream.getFields()) {
                Field real=declared.get(field.getName()); // generic type when a real field backs it
                result.put(field.getName(),real!=null && real.getType()==field.getType()?real.getGenericType():field.getType());
            }
            return result;
        }
        for(Field field:type.getDeclaredFields())
            if(!Modifier.isStatic(field.getModifiers()) && !Modifier.isTransient(field.getModifiers()))
                result.put(field.getName(),field.getGenericType());
        return result;
    }
    private static Class<?> erasure(Type type) {
        if(type instanceof Class<?>) return (Class<?>)type;
        if(type instanceof ParameterizedType) return erasure(((ParameterizedType)type).getRawType());
        if(type instanceof WildcardType) return erasure(((WildcardType)type).getUpperBounds()[0]);
        if(type instanceof TypeVariable<?>) return erasure(((TypeVariable<?>)type).getBounds()[0]);
        if(type instanceof GenericArrayType)
            return java.lang.reflect.Array.newInstance(erasure(((GenericArrayType)type).getGenericComponentType()),0).getClass();
        throw new IllegalStateException("Unexpected type "+type);
    }
    /**
     * The named class or array when the checkpoint allowlist admits it (checked by name first, so
     * nothing else is loaded) and no desktop UI class is its element type; otherwise null.
     */
    private static Class<?> admitted(String name,Set<String> allowlist,Method allowed,Class<?> component,ClassLoader loader) throws Exception {
        String element=name.replaceFirst("^\\[+","");
        if(name.startsWith("[")) {
            if(!element.startsWith("L")) return Class.forName(name,false,loader); // primitive elements
            element=element.substring(1,element.length()-1);
        }
        if(!allowlist.contains(element) && Arrays.stream(CHECKPOINT_PACKAGES).noneMatch(element::startsWith)) return null;
        Class<?> type=Class.forName(name,false,loader),base=type;
        while(base.isArray()) base=base.getComponentType();
        return component.isAssignableFrom(base) || !(Boolean)allowed.invoke(null,type)?null:type;
    }
    /**
     * Reads the class files under these roots: adds the array types their code creates and the
     * classes their code loads as class literals to the two sets (Class.getName form).
     */
    private static void scanEngineCode(List<Path> roots,Set<String> arrays,Set<String> literals) throws Exception {
        for(Path root:roots)
            try(Stream<Path> paths=Files.walk(root)) {
                for(Path path:(Iterable<Path>)paths.filter(p->p.toString().endsWith(".class"))::iterator)
                    scanClassFile(Files.readAllBytes(path),arrays,literals);
            }
    }
    /** Instruction lengths (JVMS 6.5); 0 marks tableswitch, lookupswitch, wide and unassigned opcodes. */
    private static final byte[] OPCODE_LENGTH=new byte[256];
    static {
        Arrays.fill(OPCODE_LENGTH,0,0xca+1,(byte)1);
        for(int op:new int[]{0x10,0x12,0x15,0x16,0x17,0x18,0x19,0x36,0x37,0x38,0x39,0x3a,0xa9,0xbc}) OPCODE_LENGTH[op]=2;
        for(int op:new int[]{0x11,0x13,0x14,0x84,0xb2,0xb3,0xb4,0xb5,0xb6,0xb7,0xb8,0xbb,0xbd,0xc0,0xc1,0xc6,0xc7}) OPCODE_LENGTH[op]=3;
        for(int op=0x99;op<=0xa8;op++) OPCODE_LENGTH[op]=3;
        OPCODE_LENGTH[0xc5]=4;
        for(int op:new int[]{0xb9,0xba,0xc8,0xc9}) OPCODE_LENGTH[op]=5;
        for(int op:new int[]{0xaa,0xab,0xc4}) OPCODE_LENGTH[op]=0;
    }
    private static final String PRIMITIVE_ARRAYS="????ZCFDBSIJ"; // newarray atype 4..11
    /**
     * Adds the array types created by anewarray, multianewarray and newarray in one class file,
     * and the class literals loaded by ldc (JVMS 4.4 constant pool, 4.7.3 Code attribute, 6.5).
     * Anything unexpected fails the export.
     */
    static void scanClassFile(byte[] bytes,Set<String> sink,Set<String> literals) {
        java.nio.ByteBuffer in=java.nio.ByteBuffer.wrap(bytes);
        if(in.getInt()!=0xCAFEBABE) throw new IllegalStateException("Not a class file");
        in.position(8);
        int count=Short.toUnsignedInt(in.getShort());
        String[] utf8=new String[count];int[] classNames=new int[count];
        for(int i=1;i<count;i++) {
            int tag=in.get()&0xff;
            switch(tag) {
                case 1: { byte[] text=new byte[Short.toUnsignedInt(in.getShort())];in.get(text);
                          utf8[i]=new String(text,java.nio.charset.StandardCharsets.UTF_8);break; }
                case 7: classNames[i]=Short.toUnsignedInt(in.getShort());break;
                case 8: case 16: case 19: case 20: in.position(in.position()+2);break;
                case 15: in.position(in.position()+3);break;
                case 3: case 4: case 9: case 10: case 11: case 12: case 17: case 18: in.position(in.position()+4);break;
                case 5: case 6: in.position(in.position()+8);i++;break;
                default: throw new IllegalStateException("Unknown constant pool tag "+tag);
            }
        }
        in.position(in.position()+6); // access flags, this class, superclass
        int interfaces=Short.toUnsignedInt(in.getShort());
        in.position(in.position()+2*interfaces);
        for(int kind=0;kind<2;kind++) { // fields, then methods
            for(int member=Short.toUnsignedInt(in.getShort());member>0;member--) {
                in.position(in.position()+6);
                for(int attribute=Short.toUnsignedInt(in.getShort());attribute>0;attribute--) {
                    String name=utf8[Short.toUnsignedInt(in.getShort())];
                    int length=in.getInt(),end=in.position()+length;
                    if(kind==1 && name.equals("Code")) {
                        in.position(in.position()+4);
                        int size=in.getInt(),start=in.position();
                        for(int pc=0;pc<size;) {
                            int op=bytes[start+pc]&0xff,at=start+pc+1;
                            if(op==0xbd || op==0xc5) { // anewarray COMPONENT / multianewarray ARRAY
                                String type=utf8[classNames[((bytes[at]&0xff)<<8)|(bytes[at+1]&0xff)]].replace('/','.');
                                sink.add(op==0xc5?type:type.startsWith("[")?"["+type:"[L"+type+";");
                            } else if(op==0xbc) sink.add("["+PRIMITIVE_ARRAYS.charAt(bytes[at]));
                            else if(op==0x12 || op==0x13) { // ldc / ldc_w
                                int index=op==0x12?bytes[at]&0xff:((bytes[at]&0xff)<<8)|(bytes[at+1]&0xff);
                                if(classNames[index]!=0) literals.add(utf8[classNames[index]].replace('/','.'));
                            }
                            int step=OPCODE_LENGTH[op];
                            if(op==0xaa || op==0xab) {
                                int table=start+((pc+4)&~3); // 0-3 padding bytes after the opcode
                                java.nio.ByteBuffer operands=java.nio.ByteBuffer.wrap(bytes,table+4,8);
                                int low=operands.getInt(),high=operands.getInt();
                                step=table-(start+pc)+(op==0xaa?12+4*(high-low+1):8+8*low);
                            } else if(op==0xc4) step=(bytes[at]&0xff)==0x84?6:4;
                            if(step<=0) throw new IllegalStateException("Unexpected opcode "+op+" at "+pc);
                            pc+=step;
                        }
                    }
                    in.position(end);
                }
            }
        }
    }
    private static Set<String> classNames(Path root,String prefix) throws Exception {
        Set<String> names=new TreeSet<>();
        try(Stream<Path> paths=Files.walk(root)) {
            paths.filter(p->p.toString().endsWith(".class")).forEach(p->{
                String name=root.relativize(p).toString().replace(java.io.File.separatorChar,'.');
                if(name.startsWith(prefix) && !name.equals("module-info.class")) names.add(name.substring(0,name.length()-6));
            });
        }
        return names;
    }

    private static Map<String,Object> entry(Class<?> type) {
        return entries.computeIfAbsent(type.getName(),name->Json.map("name",name));
    }
    private static void visit(Type type) {
        if(type==null || !seenTypes.add(type))return;
        if(type instanceof ParameterizedType) {
            ParameterizedType p=(ParameterizedType)type;visit(p.getRawType());
            for(Type t:p.getActualTypeArguments())visit(t);
        } else if(type instanceof GenericArrayType) {
            visit(((GenericArrayType)type).getGenericComponentType());
        } else if(type instanceof WildcardType) {
            for(Type t:((WildcardType)type).getUpperBounds())visit(t);
        } else if(type instanceof TypeVariable<?>) {
            for(Type t:((TypeVariable<?>)type).getBounds())visit(t);
        } else if(type instanceof Class<?>) {
            Class<?> c=(Class<?>)type;
            if(c.isArray()){visit(c.getComponentType());return;}
            if(!c.getName().startsWith("mage."))return; // Gson's standard JDK adapters own those types.
            dtoTypes.add(c.getName());entry(c).put("allDeclaredFields",true);
            visit(c.getGenericSuperclass());
            for(Type parent:c.getGenericInterfaces())visit(parent);
            if(!c.isEnum())for(Field field:c.getDeclaredFields())
                if(!Modifier.isStatic(field.getModifiers())&&!Modifier.isTransient(field.getModifiers()))
                    visit(field.getGenericType());
        }
    }
}
