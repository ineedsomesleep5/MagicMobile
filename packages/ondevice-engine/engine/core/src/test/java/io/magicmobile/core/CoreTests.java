package io.magicmobile.core;

import java.util.*;
import java.util.concurrent.*;
import java.math.BigDecimal;

/** No fake rules engine. Tests ONLY the transport/security/concurrency boundary. */
public final class CoreTests {
    private static int checks;
    private static void ok(boolean b,String label) {checks++;if(!b)throw new AssertionError(label);}
    private static void error(String code,Runnable r) {
        checks++;try {r.run();throw new AssertionError("Expected "+code);}
        catch(BridgeException e) {if(!code.equals(e.code()))throw new AssertionError("Expected "+code+", got "+e.code(),e);}
    }
    private static DecisionSpec spec(String type) {return new DecisionSpec("ASK",Json.map(),Set.of(type),null,null,0,10,null);}
    private static Map<String,Object> command(Map<String,Object> prompt,String request,Object answer) {
        return Json.map("requestId",request,"promptId",prompt.get("promptId"),"promptRevision",prompt.get("revision"),"answer",answer);
    }
    private static Map<String,Object> answer(String kind,Object value) {return Json.map("kind",kind,"value",value);}
    private static Map<String,Object> pending(MatchMailbox m,String s) {return Json.object(m.poll(s,0).get("prompt"));}
    public static void main(String[] args) throws Exception {
        json();decisions();manaIdentity();singleRecipient();mailbox();concurrent();service();diagnostics();
        System.out.println("PASS: "+checks+" assertions; scope=standalone-core (NOT XMage gameplay or iOS)");
    }
    private static void json() {
        Object obj=Json.parse("{\"z\":[null,true,false,-2,3.5,\"🦊\\n\"],\"a\":1}");
        ok(Json.write(obj).startsWith("{\"a\":1,"),"canonical keys");
        ok(Json.write(Json.parse(Json.write(obj))).equals(Json.write(obj)),"round trip");
        for(String bad:new String[]{"","{","[1,]","{\"x\":null,\"x\":1}","true false","00","+1","NaN","1.","1e","1e+","\"\\uD800\"","\"\\uDC00\"","[","{\"x\" 1}","\"a\n\"","--2","9223372036854775808"})
            error("invalid_json",()->Json.parse(bad));
        error("invalid_json",()->Json.parse("[".repeat(66)+"0"+"]".repeat(66)));
        error("invalid_json",()->Json.parse(" ".repeat(Json.MAX_TEXT+1)));
        error("invalid_json",()->Json.integer(new BigDecimal("1.2")));
        error("invalid_json",()->Json.integer(true));
        error("invalid_json",()->Json.bool("true"));
        error("invalid_json",()->Json.object(List.of()));
        error("invalid_json",()->Json.write(Double.NaN));
        Map<String,Object> cyclic=new HashMap<>();cyclic.put("loop",cyclic);
        error("invalid_json",()->Json.freeze(cyclic));
        Map<String,Object> original=Json.map("a",new ArrayList<>(List.of(1)));
        Map<String,Object> frozen=Json.object(Json.freeze(original));Json.array(original.get("a")).add(2);
        ok(Json.array(frozen.get("a")).size()==1,"deep copy");
        ok(Json.integer(Json.parse("1e2"))==100,"exact scientific integer");
        ok(Json.write(Json.parse("\"\\uD83D\\uDE00\"")).equals("\"😀\""),"surrogate pair");
        Random random=new Random(42);
        for(int i=0;i<300;i++) {
            Map<String,Object> x=Json.map("id",i,"n",random.nextLong(),"s","hi\n\\\""+i,"a",Arrays.asList(true,null,i));
            ok(Json.write(Json.parse(Json.write(x))).equals(Json.write(x)),"random roundtrip "+i);
        }
    }
    private static void decisions() {
        spec("boolean").validate(answer("boolean",false));checks++;
        error("invalid_response",()->spec("boolean").validate(answer("integer",1)));
        error("invalid_json",()->spec("boolean").validate(answer("boolean","false")));
        error("invalid_response",()->spec("integer").validate(answer("integer",-1)));
        error("invalid_response",()->spec("integer").validate(answer("integer",11)));
        spec("integer").validate(answer("integer",10));checks++;
        Map<String,Object> extra=answer("boolean",true);extra.put("actor","other");
        error("invalid_response",()->spec("boolean").validate(extra));
        String id=UUID.randomUUID().toString();
        DecisionSpec d=new DecisionSpec("TARGET",Json.map(),Set.of("uuid"),Set.of(id),null,0,0,null);
        d.validate(answer("uuid",id));checks++;
        error("invalid_response",()->d.validate(answer("uuid",UUID.randomUUID().toString())));
        error("invalid_response",()->d.validate(answer("uuid","1-1-1-1-1")));
        DecisionSpec s=new DecisionSpec("CHOICE",Json.map(),Set.of("string"),null,Set.of("yes"),0,0,null);
        s.validate(answer("string","yes"));checks++;
        error("invalid_response",()->s.validate(answer("string","no")));
        DecisionSpec emptySpecial=new DecisionSpec("CHOOSE_CHOICE",Json.map("specialEnabled",true,"specialCanBeEmpty",true),Set.of("string"),null,Set.of("yes"),0,0,null);
        ok(emptySpecial.validate(answer("string",null)).containsKey("value"),"special empty preserves a typed null string response");
        error("invalid_response",()->emptySpecial.validate(answer("string","#")));
        error("invalid_response",()->s.validate(answer("string",null)));
        DecisionSpec notEmpty=new DecisionSpec("CHOOSE_CHOICE",Json.map("specialEnabled",true,"specialCanBeEmpty",false),Set.of("string"),null,Set.of("yes"),0,0,null);
        error("invalid_response",()->notEmpty.validate(answer("string",null)));
        DecisionSpec allocations=new DecisionSpec("MULTI",Json.map(),Set.of("integers"),null,null,5,5,List.of(new long[]{0,5},new long[]{0,5}));
        allocations.validate(answer("integers",List.of(2,3)));checks++;
        error("invalid_response",()->allocations.validate(answer("integers",List.of(2,2))));
        error("invalid_response",()->allocations.validate(answer("integers",List.of(5))));
        error("invalid_response",()->allocations.validate(answer("integers",List.of(-1,6))));
    }
    private static void manaIdentity() throws Exception {
        String acting=UUID.randomUUID().toString(),controller=UUID.randomUUID().toString();
        for(String kind:List.of("SELECT","PLAY_MANA","PLAY_X_MANA")) {
            DecisionSpec decision=new DecisionSpec(kind,Json.map("manaPlayerId",acting),Set.of("mana"),null,null,0,0,null);
            Map<String,Object> valid=answer("mana",Json.map("playerId",acting,"manaType","GREEN"));
            ok(decision.validate(valid).equals(valid),"acting mana identity preserved for "+kind);
            error("invalid_response",()->decision.validate(answer("mana",Json.map("playerId",controller,"manaType","GREEN"))));
            error("invalid_response",()->decision.validate(answer("mana",Json.map("playerId","not-a-uuid","manaType","GREEN"))));
        }
        DecisionSpec missing=new DecisionSpec("PLAY_MANA",Json.map(),Set.of("mana"),null,null,0,0,null);
        error("invalid_response",()->missing.validate(answer("mana",Json.map("playerId",acting,"manaType","GREEN"))));
        // The authenticated controller answers using the acted player's pool, not its own.
        try(MatchMailbox mailbox=new MatchMailbox("controlled-mana",List.of(controller))) {
            DecisionSpec decision=new DecisionSpec("PLAY_MANA",Json.map("manaPlayerId",acting),Set.of("mana"),null,null,0,0,null);
            CountDownLatch delivered=new CountDownLatch(1);
            List<Map<String,Object>> received=new CopyOnWriteArrayList<>();
            mailbox.ask(controller,decision,value->{received.add(value);delivered.countDown();});
            Map<String,Object> prompt=pending(mailbox,controller);
            String request=UUID.randomUUID().toString();
            error("invalid_response",()->mailbox.submit(controller,command(prompt,request,
                answer("mana",Json.map("playerId",controller,"manaType","GREEN")))));
            ok(Boolean.FALSE.equals(pending(mailbox,controller).get("submitted")),"wrong pool leaves prompt unsubmitted");
            Map<String,Object> valid=answer("mana",Json.map("playerId",acting,"manaType","GREEN"));
            mailbox.submit(controller,command(prompt,request,valid));
            ok(delivered.await(2,TimeUnit.SECONDS),"controller can answer with acting pool after rejection");
            ok(received.equals(List.of(valid)),"only exact acting-pool answer delivered");
        }
    }
    private static void singleRecipient() throws Exception {
        try(MatchMailbox m=new MatchMailbox("human-and-ai",List.of("human"))) {
            m.publishSnapshots(Map.of("human",Json.map("hand",List.of("human-secret"))));
            CountDownLatch delivered=new CountDownLatch(1);
            m.ask("human",spec("boolean"),r->delivered.countDown());
            m.inform("human",Json.map("message","private-human-message"));
            ok(Json.write(m.poll("human",0)).contains("human-secret"),"single recipient receives own snapshot");
            ok(Json.write(m.poll("human",0)).contains("private-human-message"),"single recipient receives own information");
            Map<String,Object> c=command(pending(m,"human"),UUID.randomUUID().toString(),answer("boolean",true));
            error("unauthorized_seat",()->m.poll("ai",0));
            error("unauthorized_seat",()->m.submit("ai",c));
            error("unauthorized_seat",()->m.ask("ai",spec("boolean"),r->{}));
            error("unauthorized_seat",()->m.inform("ai",Json.map("message","private")));
            long revision=m.revision();
            error("projection_error",()->m.publishSnapshots(Map.of("human",Json.map(),"ai",Json.map("hand",List.of("ai-secret")))));
            ok(m.revision()==revision,"extra AI projection is rejected atomically");
            m.submit("human",c);ok(delivered.await(2,TimeUnit.SECONDS),"single recipient answer delivered");
            m.consumed("human");ok(m.poll("human",0).get("prompt")==null,"single recipient consumption removes prompt");
            m.close();
            ok(m.poll("human",0).get("snapshot")==null,"single recipient close clears snapshot");
            ok(Json.array(m.poll("human",0).get("events")).isEmpty(),"single recipient close clears private event history");
        }
    }
    private static void mailbox() throws Exception {
        try(MatchMailbox m=new MatchMailbox("match",List.of("A","B","C","D"))) {
            Map<String,Map<String,Object>> views=new LinkedHashMap<>();
            for(String s:List.of("A","B","C","D"))views.put(s,Json.map("hand",List.of("secret-"+s)));
            m.publishSnapshots(views);
            String a=Json.write(m.poll("A",0));ok(a.contains("secret-A")&&!a.contains("secret-B"),"private hand isolation");
            error("unauthorized_seat",()->m.poll("intruder",0));
            error("invalid_cursor",()->m.poll("A",-1));
            error("invalid_cursor",()->m.poll("A",999));
            CountDownLatch delivered=new CountDownLatch(1);
            m.ask("B",spec("boolean"),r->delivered.countDown());
            ok(m.poll("A",0).get("prompt")==null,"no opponent prompt");
            Map<String,Object> p=pending(m,"B");
            Map<String,Object> c=command(p,UUID.randomUUID().toString(),answer("boolean",true));
            error("stale_prompt",()->m.submit("A",c));
            Map<String,Object> receipt=m.submit("B",c);
            ok(delivered.await(2,TimeUnit.SECONDS),"answer delivered");
            ok(Json.write(receipt).equals(Json.write(m.submit("B",c))),"idempotent duplicate");
            Map<String,Object> reordered=new TreeMap<>(c);
            ok(Json.write(receipt).equals(Json.write(m.submit("B",reordered))),"key order independent dedup");
            Map<String,Object> different=new LinkedHashMap<>(c);different.put("answer",answer("boolean",false));
            error("request_id_reused",()->m.submit("B",different));
            error("response_pending",()->m.submit("B",command(p,UUID.randomUUID().toString(),answer("boolean",false))));
            m.consumed("B");ok(m.poll("B",0).get("prompt")==null,"consumed prompt removed");
            m.ask("B",spec("boolean"),r->{});
            error("stale_prompt",()->m.submit("B",command(p,UUID.randomUUID().toString(),answer("boolean",true))));
            Map<String,Object> open=pending(m,"B");
            CountDownLatch retractedDelivery=new CountDownLatch(1);
            m.ask("C",spec("boolean"),r->retractedDelivery.countDown());
            Map<String,Object> queued=command(pending(m,"C"),UUID.randomUUID().toString(),answer("boolean",true));
            long unretracted=m.revision();m.retract("A");ok(m.revision()==unretracted,"retracting without a question changes nothing");
            m.retract("B");ok(m.poll("B",0).get("prompt")==null,"retracted question disappears");
            error("stale_prompt",()->m.submit("B",command(open,UUID.randomUUID().toString(),answer("boolean",true))));
            m.retract("C");error("stale_prompt",()->m.submit("C",queued));
            ok(!retractedDelivery.await(100,TimeUnit.MILLISECONDS),"a retracted question is never delivered");
            error("unauthorized_seat",()->m.retract("intruder"));
            long before=m.revision();
            error("projection_error",()->m.publishSnapshots(Map.of("A",Json.map())));
            ok(m.revision()==before,"partial projection not published");
            for(int i=0;i<140;i++)m.publishSnapshots(views);
            ok(Json.bool(m.poll("A",0).get("resyncRequired")),"ring overflow full resync");
            ok(m.poll("A",0).get("snapshot")!=null,"snapshot survives ring overflow");
            ok(!Json.write(m.poll("A",m.revision())).contains("secret-B"),"privacy after resync");
            m.finish();long ended=m.revision();m.finish();ok(m.revision()==ended,"finish idempotent");
            error("match_unavailable",()->m.ask("A",spec("boolean"),r->{}));
            m.close();ok(m.poll("A",0).get("snapshot")==null,"destroy erases cached secrets");
        }
        try(MatchMailbox m=new MatchMailbox("m",List.of("A","B"))) {
            m.ask("A",spec("boolean"),r->{throw new Exception("private card name");});
            m.submit("A",command(pending(m,"A"),UUID.randomUUID().toString(),answer("boolean",true)));
            long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(2);
            while(!m.poll("A",0).get("phase").equals("failed")&&System.nanoTime()<deadline)Thread.sleep(2);
            ok(m.poll("A",0).get("phase").equals("failed"),"delivery failure terminates match");
            ok(!Json.write(m.poll("A",0)).contains("private card name"),"exception data not leaked");
            ok(Json.write(EngineDiagnostics.read()).contains("private card name"),"delivery error retained only in local diagnostic");
        }
    }
    private static void concurrent() throws Exception {
        try(MatchMailbox m=new MatchMailbox("parallel",List.of("A","B"))) {
            java.util.concurrent.atomic.AtomicInteger deliveries=new java.util.concurrent.atomic.AtomicInteger();
            CountDownLatch fired=new CountDownLatch(1);
            m.ask("A",spec("boolean"),r->{deliveries.incrementAndGet();fired.countDown();});
            Map<String,Object> c=command(pending(m,"A"),UUID.randomUUID().toString(),answer("boolean",true));
            ExecutorService pool=Executors.newFixedThreadPool(8);
            try {
                List<Future<?>> all=new ArrayList<>();for(int i=0;i<64;i++)all.add(pool.submit(()->m.submit("A",c)));
                for(Future<?> f:all)f.get(2,TimeUnit.SECONDS);
                ok(fired.await(2,TimeUnit.SECONDS)&&deliveries.get()==1,"64 concurrent retries delivered once");
            } finally {pool.shutdownNow();}
        }
    }
    private static void service() {
        EnginePort port=new EnginePort() {
            public Map<String,Object> create(Map<String,Object> c) {throw new IllegalArgumentException("hidden");}
            public Map<String,Object> poll(String a,String b,long c){return Json.map();}
            public Map<String,Object> respond(String a,String b,Map<String,Object> c){return Json.map();}
            public void destroy(String id){}
            public Map<String,Object> capabilities(){return Json.map("fixture",true);}
            public void close(){}
        };
        EngineService service=new EngineService(port);
        ok(service.request("{\"protocol\":1,\"op\":\"capabilities\"}").contains("\"ok\":true"),"capabilities envelope");
        ok(service.request("{\"protocol\":2,\"op\":\"capabilities\"}").contains("protocol_mismatch"),"protocol mismatch");
        ok(service.request("{\"protocol\":1,\"op\":\"capabilities\",\"extra\":1}").contains("invalid_request"),"unknown keys rejected");
        ok(service.request("{\"protocol\":1,\"op\":\"create\",\"configuration\":{}}").contains("engine_failure"),"contained exception");
        ok(!service.request("{\"protocol\":1,\"op\":\"create\",\"configuration\":{}}").contains("hidden"),"sanitized error");
        String diagnostic=service.request("{\"protocol\":1,\"op\":\"diagnostics\"}");
        ok(diagnostic.contains("IllegalArgumentException") && diagnostic.contains("hidden"),"trusted local diagnostics retain the actual exception");
        ok(service.request("{\"protocol\":1,\"op\":\"diagnostics\",\"viewerId\":\"A\"}").contains("invalid_request"),"diagnostics never accepts a viewer or peer payload");
        ok(service.request("{\"protocol\":1,\"op\":\"clearDiagnostics\"}").contains("\"ok\":true"),"local diagnostics can be cleared");
        ok(service.request("{\"protocol\":1,\"op\":\"diagnostics\"}").contains("\"report\":null"),"cleared report releases private data");
        ok(service.request("{\"protocol\":1,\"op\":\"concede\",\"matchId\":\"m\",\"viewerId\":\"A\"}").contains("concede_unavailable"),"older backends cannot concede");
        ok(service.request("{\"protocol\":1,\"op\":\"concede\",\"matchId\":\"m\"}").contains("invalid_request"),"concede needs the authenticated seat");
        ok(service.request("{\"protocol\":1,\"op\":\"nonsense\"}").contains("unknown_operation"),"operation whitelist");
        ok(service.request("bad").contains("invalid_json"),"malformed request");
    }
    private static void diagnostics() {
        RuntimeException first=new RuntimeException("private diagnostic message");
        RuntimeException second=new RuntimeException("cause message",first);first.initCause(second);
        EngineDiagnostics.capture("fixture",first);
        String report=(String)EngineDiagnostics.read().get("report");
        ok(report.contains("cause message") && report.contains("CoreTests"),"cause and call site retained");
        ok(report.contains("cyclic causes omitted"),"cyclic causes bounded");
        Throwable huge=new RuntimeException("private-".repeat(10000));
        StackTraceElement[] frames=new StackTraceElement[100];
        Arrays.fill(frames,new StackTraceElement("Class".repeat(1000),"method","File.java",1));
        huge.setStackTrace(frames);EngineDiagnostics.capture("fixture",huge);
        report=(String)EngineDiagnostics.read().get("report");
        ok(report.length()<=EngineDiagnostics.MAX_CHARS,"stored report bounded");
        ok(!report.contains("cause message"),"only newest report retained");
        ok(Json.parseObject(Json.write(EngineDiagnostics.read())).containsKey("report"),"bounded report serializes");
        EngineDiagnostics.clear();ok(EngineDiagnostics.read().get("report")==null,"clear releases report");
    }
}
