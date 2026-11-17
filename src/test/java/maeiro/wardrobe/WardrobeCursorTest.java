package maeiro.wardrobe;

import java.lang.reflect.Field;
import java.lang.reflect.Proxy;
import viewpoint.api.AddonCamera;
import viewpoint.api.AddonContext;
import viewpoint.api.AddonView;
import viewpoint.api.Registration;
import viewpoint.api.camera.CursorClaim;
import viewpoint.api.view.ViewListener;

public final class WardrobeCursorTest {
    private static int acquired;
    private static int released;
    private static ViewListener listener;

    public static void main(String[] args) throws Exception {
        AddonCamera camera = (AddonCamera) Proxy.newProxyInstance(AddonCamera.class.getClassLoader(),
                new Class<?>[]{AddonCamera.class}, (proxy, method, values) -> {
                    if (!method.getName().equals("cursor")) throw new AssertionError(method);
                    acquired++;
                    return new CursorClaim() {
                        private boolean closed;
                        public boolean held() { return !closed; }
                        public void close() {
                            if (closed) throw new AssertionError("Claim closed twice");
                            closed = true;
                            released++;
                        }
                    };
                });
        AddonView view = (AddonView) Proxy.newProxyInstance(AddonView.class.getClassLoader(),
                new Class<?>[]{AddonView.class}, (proxy, method, values) -> {
                    if (!method.getName().equals("listen")) throw new AssertionError(method);
                    listener = (ViewListener) values[0];
                    return (Registration) () -> {};
                });
        AddonContext context = (AddonContext) Proxy.newProxyInstance(AddonContext.class.getClassLoader(),
                new Class<?>[]{AddonContext.class}, (proxy, method, values) -> switch (method.getName()) {
                    case "camera" -> camera;
                    case "view" -> view;
                    default -> throw new AssertionError(method);
                });
        WardrobeCursor addon = new WardrobeCursor();
        check(!WardrobeCursor.setOpen(true));
        addon.enable(context);
        check(WardrobeCursor.setOpen(true));
        check(WardrobeCursor.setOpen(true));
        check(acquired == 1 && released == 0);
        WardrobeCursor.setOpen(false);
        WardrobeCursor.setOpen(false);
        check(released == 1);
        WardrobeCursor.setOpen(true);
        Field signal = WardrobeCursor.class.getDeclaredField("lastSignalNanos");
        signal.setAccessible(true);
        signal.setLong(addon, System.nanoTime() - 3_000_000_000L);
        listener.onFrame(null);
        check(acquired == 2 && released == 2);
        WardrobeCursor.setOpen(true);
        addon.disable();
        check(acquired == 3 && released == 3);
        check(!WardrobeCursor.setOpen(true));
        addon.enable(context);
        WardrobeCursor.setOpen(true);
        addon.disable();
        check(acquired == 4 && released == 4);
        System.out.println("PASS: acquire/reuse/release, stale UI timeout, disable, and re-enable.");
    }

    private static void check(boolean condition) {
        if (!condition) throw new AssertionError();
    }
}
