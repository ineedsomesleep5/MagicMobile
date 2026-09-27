package io.magicmobile.xmage;

import io.magicmobile.core.BridgeException;
import io.magicmobile.core.EngineDiagnostics;
import io.magicmobile.core.EngineService;
import io.magicmobile.core.Json;
import io.magicmobile.generated.EngineBuildIdentity;
import io.magicmobile.generated.GeneratedCardFactory;
import mage.abilities.Ability;
import mage.abilities.MageSingleton;
import mage.cards.Card;
import mage.cards.CardSetInfo;
import mage.constants.Rarity;
import mage.game.Exile;
import mage.game.Game;
import mage.util.RandomUtil;
import java.io.*;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.zip.Deflater;
import java.util.zip.GZIPInputStream;
import java.util.zip.GZIPOutputStream;

/**
 * Save/resume files for solo games (docs/PROTOCOL.md). A checkpoint holds every hand and
 * library: it stays in the app's private storage and never enters a poll, event or peer message.
 *
 * Layout: 8-byte magic, u16 format, u32 header length, UTF-8 JSON header, then the gzip'd
 * Java serialization of {@link Payload}. The header's payloadSha256 covers the gzip bytes.
 * Reads go through one class allowlist ({@link #allowed}) that the writer also enforces, so
 * the engine never writes a checkpoint it would refuse to read, and the native build registers
 * the same classes (tools/NativeReflectionExporter).
 */
final class Checkpoints {
    static final int FORMAT=1;
    private static final byte[] MAGIC="MMCHKPT\n".getBytes(StandardCharsets.US_ASCII);
    private static final int PREFIX=MAGIC.length+2+4;
    static final int MAX_HEADER=64*1024;
    static final long MAX_PAYLOAD=64L*1024*1024;
    // Deserialization bounds. Measured 2- and 4-seat games: depth 22, 75k references, 0.8 MB stream
    // (RealCheckpointTests prints them); the limits leave 40x or more headroom.
    static final long MAX_STREAM_BYTES=128L*1024*1024, MAX_REFERENCES=4_000_000, MAX_DEPTH=1_000, MAX_ARRAY=1_000_000;
    private static final String[] PACKAGES={"mage.","io.magicmobile.xmage."};
    /**
     * JDK types a game may contain. Anything else, including proxies and every serializable lambda
     * (java.lang.invoke.SerializedLambda), is refused both ways. Upstream conditions and predicates
     * that were lambdas are named classes (scripts/prepare_upstream.py), so no game state needs one.
     */
    private static final Set<String> JDK_TYPES=Set.of(
        // Object and Map.Entry appear only as array components the JDK collections pre-check.
        "java.lang.Object","java.util.Map$Entry","java.lang.Enum","java.lang.Number","java.lang.Boolean","java.lang.Byte",
        "java.lang.Character","java.lang.Short","java.lang.Integer","java.lang.Long","java.lang.Float",
        "java.lang.Double","java.lang.String","java.lang.String$CaseInsensitiveComparator",
        "java.math.BigInteger","java.math.BigDecimal",
        "java.util.ArrayList","java.util.LinkedList","java.util.ArrayDeque","java.util.PriorityQueue",
        "java.util.Vector","java.util.Stack","java.util.HashMap","java.util.LinkedHashMap","java.util.TreeMap",
        "java.util.IdentityHashMap","java.util.EnumMap","java.util.HashSet","java.util.LinkedHashSet",
        "java.util.TreeSet","java.util.EnumSet$SerializationProxy","java.util.UUID","java.util.Date",
        // readResolve results, which newer JDKs also pass through the filter.
        "java.util.RegularEnumSet","java.util.JumboEnumSet","java.util.ImmutableCollections$ListN",
        "java.util.ImmutableCollections$List12","java.util.ImmutableCollections$SetN","java.util.ImmutableCollections$Set12",
        "java.util.ImmutableCollections$MapN","java.util.ImmutableCollections$Map1",
        "java.util.Random","java.util.BitSet","java.util.AbstractMap$SimpleEntry",
        "java.util.AbstractMap$SimpleImmutableEntry","java.util.Arrays$ArrayList","java.util.CollSer",
        "java.util.Collections$EmptyList","java.util.Collections$EmptyMap","java.util.Collections$EmptySet",
        "java.util.Collections$SingletonList","java.util.Collections$SingletonMap","java.util.Collections$SingletonSet",
        "java.util.Collections$UnmodifiableCollection","java.util.Collections$UnmodifiableList",
        "java.util.Collections$UnmodifiableRandomAccessList","java.util.Collections$UnmodifiableSet",
        "java.util.Collections$UnmodifiableSortedSet","java.util.Collections$UnmodifiableMap",
        "java.util.Collections$UnmodifiableSortedMap","java.util.Collections$SynchronizedCollection",
        "java.util.Collections$SynchronizedList","java.util.Collections$SynchronizedRandomAccessList",
        "java.util.Collections$SynchronizedSet","java.util.Collections$SynchronizedMap",
        "java.util.Collections$ReverseComparator","java.util.concurrent.ConcurrentHashMap",
        "java.util.concurrent.ConcurrentHashMap$Segment","java.util.concurrent.ConcurrentLinkedQueue",
        "java.util.concurrent.ConcurrentLinkedDeque","java.util.concurrent.ConcurrentSkipListMap",
        "java.util.concurrent.ConcurrentSkipListSet","java.util.concurrent.CopyOnWriteArrayList",
        "java.util.concurrent.CopyOnWriteArraySet","java.util.concurrent.LinkedBlockingQueue",
        "java.util.concurrent.LinkedBlockingDeque","java.util.concurrent.atomic.AtomicBoolean",
        "java.util.concurrent.atomic.AtomicInteger","java.util.concurrent.atomic.AtomicLong",
        "java.util.concurrent.atomic.AtomicReference","java.util.concurrent.locks.ReentrantLock",
        "java.util.concurrent.locks.ReentrantLock$Sync","java.util.concurrent.locks.ReentrantLock$NonfairSync",
        "java.util.concurrent.locks.ReentrantLock$FairSync","java.util.concurrent.locks.AbstractQueuedSynchronizer",
        "java.util.concurrent.locks.AbstractOwnableSynchronizer");
    private static volatile Boolean available;
    /**
     * Tests only; null in production. Sees each admitted class that a stream writes as a class
     * descriptor (object, superclass, enum, array, Class object) and each one a read resolves or
     * gets back from readResolve. A native image resolves every stream class through Class.forName,
     * so RealCheckpointTests requires all of them in the exported native metadata.
     */
    static volatile java.util.function.Consumer<Class<?>> classObserver;

    private Checkpoints() {}

    /** The whole match state, plus the process-global RNG, captured at a human priority decision. */
    static final class Payload implements Serializable {
        private static final long serialVersionUID=1L;
        final MobileCommanderGame game;
        final LinkedHashMap<String,UUID> seats;
        final ArrayList<String> humanSeats;
        final Random random;
        Payload(MobileCommanderGame game,LinkedHashMap<String,UUID> seats,ArrayList<String> humanSeats,Random random) {
            this.game=game;this.seats=seats;this.humanSeats=humanSeats;this.random=random;
        }
    }
    static final class Written {
        final long sequence,savedAtMillis,bytes,writeMillis; final int turn;
        Written(long sequence,long savedAtMillis,int turn,long bytes,long writeMillis) {
            this.sequence=sequence;this.savedAtMillis=savedAtMillis;this.turn=turn;this.bytes=bytes;this.writeMillis=writeMillis;
        }
    }
    static final class Loaded {
        final Payload payload; final Map<String,Object> header; final long bytes;
        Loaded(Payload payload,Map<String,Object> header,long bytes) { this.payload=payload;this.header=header;this.bytes=bytes; }
        long sequence() { return Json.integer(header.get("sequence")); }
        long savedAtMillis() { return Json.integer(header.get("savedAtMillis")); }
        int turn() { return Math.toIntExact(Json.integer(header.get("turn"))); }
    }

    static Set<String> jdkTypes() { return JDK_TYPES; }
    static boolean allowed(Class<?> type) {
        while(type.isArray()) type=type.getComponentType();
        if(type.isPrimitive()) return true;
        String name=type.getName();
        if(java.lang.reflect.Proxy.isProxyClass(type)) return false;
        for(String prefix:PACKAGES) if(name.startsWith(prefix)) return true;
        return JDK_TYPES.contains(name);
    }

    /** True only when this build can write and read checkpoints (the native image needs serialization metadata). */
    static boolean available() {
        Boolean value=available;
        if(value!=null) return value;
        synchronized(Checkpoints.class) {
            if(available==null) available=selfTest();
            return available;
        }
    }
    private static boolean selfTest() {
        try {
            // A real Mage.Sets card with its abilities, a game zone, collections and the RNG type,
            // through the production writer, digest, filter and reader.
            UUID owner=UUID.randomUUID();
            Card card=new mage.cards.s.SwordsToPlowshares(owner,new CardSetInfo("Swords to Plowshares","ICE","54",Rarity.UNCOMMON));
            Exile exile=new Exile();
            exile.createZone(owner,"Probe").add(card);
            LinkedHashMap<String,Object> probe=new LinkedHashMap<>();
            probe.put("card",card);probe.put("exile",exile);probe.put("random",new Random(7));
            probe.put("zones",new EnumMap<>(mage.constants.Zone.class));probe.put("owner",owner);
            probe.put("zoneSet",EnumSet.of(mage.constants.Zone.BATTLEFIELD,mage.constants.Zone.GRAVEYARD));
            probe.put("list",new ArrayList<>(List.of(owner)));probe.put("linked",new LinkedList<>(List.of(1)));
            // Conditions are named Serializable classes, never lambdas (see ProbeCondition).
            probe.put("condition",new ProbeCondition(7));
            byte[] bytes=serialize(probe);
            Map<?,?> read=(Map<?,?>)deserialize(bytes);
            Card copy=(Card)read.get("card");
            if(!copy.getId().equals(card.getId()) || !copy.getName().equals(card.getName())
                || ((Exile)read.get("exile")).getExileZone(owner).size()!=1
                || ((Random)read.get("random")).nextLong()!=new Random(7).nextLong()
                || !read.get("zoneSet").equals(probe.get("zoneSet")) || !read.get("list").equals(probe.get("list"))
                || !((mage.abilities.condition.Condition)read.get("condition")).apply(null,null))
                throw new IllegalStateException("Checkpoint self-test read different values");
            return true;
        } catch(Throwable failure) {
            EngineDiagnostics.capture("checkpoint-self-test",failure);
            return false;
        }
    }

    /**
     * A named Serializable Condition with state, like the upstream ones prepare_upstream.py turns
     * lambdas into. No lambda here: a class with a serializable lambda would need GraalVM
     * lambdaCapturingTypes metadata, which breaks the pinned native build (docs/NATIVE_METADATA.md).
     */
    private static final class ProbeCondition implements mage.abilities.condition.Condition {
        private static final long serialVersionUID=1L;
        private final int expected;
        ProbeCondition(int expected) { this.expected=expected; }
        @Override public boolean apply(Game game,Ability source) { return expected==7; }
    }

    /**
     * Runs on the GAME thread at a human priority safe point, only when the app asked for a save
     * (XmageEngine: before that prompt is published, or while it waits for an answer).
     */
    static Written write(Path path,MobileCommanderGame game,LinkedHashMap<String,UUID> seats,ArrayList<String> humanSeats,
                         List<Map<String,Object>> seatSummary,long sequence) throws IOException {
        long start=System.nanoTime();
        // Lean: an AI's retained search tree is a whole game copy that a late simulation thread
        // may still be changing. It is recalculated after a restore.
        Runnable reattach=MobileAICancellation.detachSearchTrees(game);
        byte[] payload;
        try { payload=serialize(new Payload(game,seats,humanSeats,RandomUtil.getRandom())); }
        finally { reattach.run(); }
        long savedAt=System.currentTimeMillis();
        int turn=game.getTurnNum();
        byte[] header=Json.write(Json.map("format",FORMAT,"protocol",EngineService.PROTOCOL,
            "upstream",XmageEngine.UPSTREAM,"catalogueHash",GeneratedCardFactory.CATALOGUE_HASH,
            "engineBuild",EngineBuildIdentity.VALUE,"sequence",sequence,"savedAtMillis",savedAt,"turn",turn,
            "seats",seatSummary,"payloadBytes",(long)payload.length,"payloadSha256",sha256(payload))).getBytes(StandardCharsets.UTF_8);
        if(header.length>MAX_HEADER || payload.length>MAX_PAYLOAD) throw new IOException("Checkpoint too large to restore");
        Path temporary=path.resolveSibling(path.getFileName()+".tmp");
        try(FileChannel out=FileChannel.open(temporary,StandardOpenOption.CREATE,StandardOpenOption.WRITE,StandardOpenOption.TRUNCATE_EXISTING)) {
            ByteBuffer prefix=ByteBuffer.allocate(PREFIX).put(MAGIC).putShort((short)FORMAT).putInt(header.length);
            prefix.flip();
            writeFully(out,prefix);writeFully(out,ByteBuffer.wrap(header));writeFully(out,ByteBuffer.wrap(payload));
            out.force(true);
        }
        Files.move(temporary,path,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);
        try(FileChannel directory=FileChannel.open(path.toAbsolutePath().getParent(),StandardOpenOption.READ)) {
            directory.force(true); // Makes the rename durable where the platform allows it.
        } catch(IOException | UnsupportedOperationException ignored) {}
        long bytes=PREFIX+header.length+payload.length;
        return new Written(sequence,savedAt,turn,bytes,(System.nanoTime()-start)/1_000_000);
    }
    private static void writeFully(FileChannel out,ByteBuffer buffer) throws IOException {
        while(buffer.hasRemaining()) out.write(buffer);
    }

    /** Throws checkpoint_corrupt or checkpoint_incompatible; never returns partial state. */
    static Loaded read(Path path) {
        byte[] file;
        try {
            if(!Files.isRegularFile(path)) throw corrupt("No checkpoint file exists at this path",null);
            if(Files.size(path)>PREFIX+MAX_HEADER+MAX_PAYLOAD) throw corrupt("The checkpoint file is too large",null);
            file=Files.readAllBytes(path);
        } catch(IOException e) { throw corrupt("The checkpoint file could not be read",e); }
        if(file.length<PREFIX || !Arrays.equals(Arrays.copyOf(file,MAGIC.length),MAGIC))
            throw corrupt("The file is not a checkpoint or is truncated",null);
        ByteBuffer prefix=ByteBuffer.wrap(file,MAGIC.length,6);
        int format=Short.toUnsignedInt(prefix.getShort()),headerLength=prefix.getInt();
        if(format!=FORMAT) throw incompatible("Checkpoint format "+format+" is not supported by this engine");
        if(headerLength<2 || headerLength>MAX_HEADER || PREFIX+(long)headerLength>file.length)
            throw corrupt("The checkpoint header is truncated or invalid",null);
        Map<String,Object> header;
        try { header=Json.parseObject(new String(file,PREFIX,headerLength,StandardCharsets.UTF_8)); }
        catch(RuntimeException e) { throw corrupt("The checkpoint header is not valid JSON",e); }
        long payloadBytes;String payloadSha;
        try {
            Json.onlyKeys(header,Set.of("format","protocol","upstream","catalogueHash","engineBuild","sequence",
                "savedAtMillis","turn","seats","payloadBytes","payloadSha256"));
            if(Json.integer(header.get("format"))!=FORMAT) throw incompatible("Checkpoint format differs from this engine");
            if(Json.integer(header.get("protocol"))!=EngineService.PROTOCOL) throw incompatible("Checkpoint protocol differs from this engine");
            if(!XmageEngine.UPSTREAM.equals(Json.requiredString(header,"upstream"))) throw incompatible("Checkpoint was saved by a different XMage version");
            if(!GeneratedCardFactory.CATALOGUE_HASH.equals(Json.requiredString(header,"catalogueHash"))) throw incompatible("Checkpoint was saved with a different card catalogue");
            if(!EngineBuildIdentity.VALUE.equals(Json.requiredString(header,"engineBuild"))) throw incompatible("Checkpoint was saved by a different engine build");
            Json.integer(header.get("sequence"));Json.integer(header.get("savedAtMillis"));Json.integer(header.get("turn"));
            Json.array(header.get("seats"));
            payloadBytes=Json.integer(header.get("payloadBytes"));payloadSha=Json.requiredString(header,"payloadSha256");
        } catch(BridgeException e) {
            if(e.code().startsWith("checkpoint_")) throw e;
            throw corrupt("The checkpoint header is incomplete",e);
        }
        if(payloadBytes<1 || payloadBytes>MAX_PAYLOAD || PREFIX+(long)headerLength+payloadBytes!=file.length)
            throw corrupt("The checkpoint file is truncated or has extra bytes",null);
        byte[] payload=Arrays.copyOfRange(file,PREFIX+headerLength,file.length);
        if(!sha256(payload).equals(payloadSha)) throw corrupt("The checkpoint does not match its SHA-256",null);
        Object value;
        try { value=deserialize(payload); }
        catch(Exception | LinkageError | StackOverflowError | OutOfMemoryError e) { throw corrupt("The checkpoint could not be read safely",e); }
        if(!(value instanceof Payload)) throw corrupt("The checkpoint holds an unexpected object",null);
        return new Loaded((Payload)value,header,file.length);
    }

    static byte[] serialize(Object value) throws IOException {
        ByteArrayOutputStream bytes=new ByteArrayOutputStream(256*1024);
        CheckedOutput out=new CheckedOutput(new BufferedOutputStream(new FastGzip(bytes),64*1024));
        try(out) { out.writeObject(value); }
        catch(InvalidClassException e) {
            // ObjectOutputStream then writes the exception into the stream, which the allowlist also
            // refuses, hiding the cause. Report the class that was refused first.
            if(out.refused!=null && out.refused!=e) throw out.refused;
            throw e;
        }
        return bytes.toByteArray();
    }
    static Object deserialize(byte[] payload) throws IOException,ClassNotFoundException {
        long[] peak=new long[3];
        try(ObjectInputStream in=new ObjectInputStream(new BufferedInputStream(new GZIPInputStream(new ByteArrayInputStream(payload),64*1024),64*1024))) {
            in.setObjectInputFilter(info->{
                peak[0]=Math.max(peak[0],info.depth());peak[1]=Math.max(peak[1],info.references());peak[2]=Math.max(peak[2],info.streamBytes());
                return filter(info);
            });
            return in.readObject();
        } finally { lastRead=peak; }
    }
    /** Depth, references and stream bytes of the latest read, for measurements against the limits. */
    static volatile long[] lastRead=new long[3];
    static ObjectInputFilter.Status filter(ObjectInputFilter.FilterInfo info) {
        if(info.depth()>MAX_DEPTH || info.references()>MAX_REFERENCES || info.streamBytes()>MAX_STREAM_BYTES
                || info.arrayLength()>MAX_ARRAY) return ObjectInputFilter.Status.REJECTED;
        Class<?> type=info.serialClass();
        if(type==null) return ObjectInputFilter.Status.ALLOWED; // limit-only callback
        if(!allowed(type)) return ObjectInputFilter.Status.REJECTED;
        // A negative length: a resolved stream class or a readResolve result. Non-negative lengths
        // are array contents, including the JDK collections' checkArray pre-checks (Map.Entry[]).
        java.util.function.Consumer<Class<?>> observer=classObserver;
        if(observer!=null && info.arrayLength()<0) observer.accept(type);
        return ObjectInputFilter.Status.ALLOWED;
    }

    /**
     * Keyword singletons (Flying and similar) resolve to this process's instance, which no card
     * constructor has touched yet. Give them a source the way the first card constructed in a
     * process does, so they behave as in an uninterrupted process.
     */
    static void rehydrateSingletons(Game game) {
        for(Card card:game.getCards())
            for(Ability ability:card.getAbilities())
                if(ability instanceof MageSingleton && ability.getSourceId()==null) ability.setSourceId(card.getId());
    }

    private static final class FastGzip extends GZIPOutputStream {
        FastGzip(OutputStream out) throws IOException { super(out,64*1024);def.setLevel(Deflater.BEST_SPEED); }
    }
    /** Refuses, at write time, any class a restore would refuse. */
    private static final class CheckedOutput extends ObjectOutputStream {
        InvalidClassException refused;
        CheckedOutput(OutputStream out) throws IOException { super(out); }
        @Override protected void annotateClass(Class<?> type) throws IOException {
            if(!allowed(type)) throw refuse(new InvalidClassException(type.getName(),"Class is not allowed in a checkpoint"));
            java.util.function.Consumer<Class<?>> observer=classObserver;
            if(observer!=null) observer.accept(type); // every class descriptor this stream writes
        }
        @Override protected void annotateProxyClass(Class<?> type) throws IOException {
            throw refuse(new InvalidClassException(type.getName(),"Proxies are not allowed in a checkpoint"));
        }
        private InvalidClassException refuse(InvalidClassException e) { if(refused==null) refused=e; return e; }
    }
    static String sha256(byte[] data) {
        try {
            byte[] digest=MessageDigest.getInstance("SHA-256").digest(data);
            StringBuilder text=new StringBuilder(64);
            for(byte b:digest) text.append(Character.forDigit((b>>4)&15,16)).append(Character.forDigit(b&15,16));
            return text.toString();
        } catch(java.security.NoSuchAlgorithmException e) { throw new IllegalStateException(e); }
    }
    static BridgeException corrupt(String message,Throwable cause) {
        if(cause!=null) EngineDiagnostics.capture("checkpoint-restore",cause);
        return new BridgeException("checkpoint_corrupt",message);
    }
    static BridgeException incompatible(String message) { return new BridgeException("checkpoint_incompatible",message); }
}
