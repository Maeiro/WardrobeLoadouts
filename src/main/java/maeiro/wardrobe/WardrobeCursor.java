package maeiro.wardrobe;

import viewpoint.api.Addon;
import viewpoint.api.AddonContext;
import viewpoint.api.camera.CursorClaim;
import viewpoint.api.lua.LuaExport;

public final class WardrobeCursor implements Addon {
    private static final long SIGNAL_TIMEOUT_NANOS = 2_000_000_000L;
    private static WardrobeCursor active;
    private AddonContext context;
    private CursorClaim cursor;
    private long lastSignalNanos;

    @Override
    public void enable(AddonContext context) {
        this.context = context;
        active = this;
        context.view().listen(state -> {
            if (cursor != null && System.nanoTime() - lastSignalNanos > SIGNAL_TIMEOUT_NANOS) {
                releaseCursor();
            }
        });
    }

    @Override
    public void disable() {
        active = null;
        releaseCursor();
        context = null;
    }

    @LuaExport
    public static boolean setOpen(boolean open) {
        WardrobeCursor addon = active;
        if (addon == null) {
            return false;
        }
        if (open) {
            addon.lastSignalNanos = System.nanoTime();
            if (addon.cursor == null) {
                addon.cursor = addon.context.camera().cursor();
            }
        } else {
            addon.releaseCursor();
        }
        return true;
    }

    private void releaseCursor() {
        CursorClaim previous = cursor;
        cursor = null;
        if (previous != null) {
            previous.close();
        }
    }
}
