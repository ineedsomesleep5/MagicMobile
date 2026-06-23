import org.jboss.remoting.ServerInvocationHandler;
import org.jboss.remoting.transporter.TransporterServer;

import java.lang.reflect.Field;

public final class MagicMobileEmbeddedServerBridge {
    private MagicMobileEmbeddedServerBridge() {
    }

    public static void main(String[] args) throws Exception {
        Thread serverThread = new Thread(() -> mage.server.Main.main(args), "xmage-server-main");
        serverThread.setDaemon(false);
        serverThread.start();

        MagicMobileBridge bridge = new MagicMobileBridge(
                MagicMobileBridge.envValue("XMAGE_HOST", "127.0.0.1"),
                Integer.parseInt(MagicMobileBridge.envValue("XMAGE_PORT", "17171")),
                MagicMobileBridge.envValue("GATEWAY_URL", "http://localhost:17171")
        );
        bridge.setFixtureManagerProvider(MagicMobileEmbeddedServerBridge::findManagerFactory);
        bridge.startHttpServer(Integer.parseInt(MagicMobileBridge.envValue("BRIDGE_PORT", "17172")));
    }

    private static mage.server.managers.ManagerFactory findManagerFactory() throws Exception {
        Field serverField = mage.server.Main.class.getDeclaredField("server");
        serverField.setAccessible(true);

        long deadline = System.currentTimeMillis() + 30_000;
        while (System.currentTimeMillis() < deadline) {
            Object server = serverField.get(null);
            mage.server.managers.ManagerFactory managerFactory = managerFactoryFromServer(server);
            if (managerFactory != null) {
                return managerFactory;
            }
            Thread.sleep(250);
        }
        throw new IllegalStateException("XMage server manager factory was not reachable from embedded fixture launcher");
    }

    private static mage.server.managers.ManagerFactory managerFactoryFromServer(Object server) throws Exception {
        if (!(server instanceof TransporterServer)) {
            return null;
        }
        Field connectorField = findField(server.getClass(), "connector");
        connectorField.setAccessible(true);
        Object connector = connectorField.get(server);
        if (connector == null) {
            return null;
        }
        ServerInvocationHandler[] handlers = ((org.jboss.remoting.transport.Connector) connector).getInvocationHandlers();
        if (handlers == null) {
            return null;
        }
        for (ServerInvocationHandler handler : handlers) {
            mage.server.managers.ManagerFactory managerFactory = managerFactoryFromHandler(handler);
            if (managerFactory != null) {
                return managerFactory;
            }
        }
        return null;
    }

    private static mage.server.managers.ManagerFactory managerFactoryFromHandler(Object handler) throws Exception {
        if (handler == null) {
            return null;
        }
        Class<?> current = handler.getClass();
        while (current != null) {
            try {
                Field field = current.getDeclaredField("managerFactory");
                field.setAccessible(true);
                Object value = field.get(handler);
                if (value instanceof mage.server.managers.ManagerFactory) {
                    return (mage.server.managers.ManagerFactory) value;
                }
            } catch (NoSuchFieldException ignored) {
            }
            current = current.getSuperclass();
        }
        return null;
    }

    private static Field findField(Class<?> type, String name) throws NoSuchFieldException {
        Class<?> current = type;
        while (current != null) {
            try {
                return current.getDeclaredField(name);
            } catch (NoSuchFieldException ignored) {
                current = current.getSuperclass();
            }
        }
        throw new NoSuchFieldException(name);
    }
}
