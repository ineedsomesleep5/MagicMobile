import java.awt.Color;
import mage.abilities.hint.HintUtils;

/** Native dependency regression only; not an XMage or iPhone gameplay test. */
public final class ColorValueProbe {
    public static void main(String[] args) throws Exception {
        Color value = new Color(101, 177, 23, 91);
        if (value.getRGB() != 0x5b65b117 || value.getRed() != 101
                || value.getGreen() != 177 || value.getBlue() != 23 || value.getAlpha() != 91) {
            throw new AssertionError("RGB/alpha value changed");
        }
        if (!Color.RED.equals(new Color(255, 0, 0)) || Color.WHITE.getRGB() != 0xffffffff
                || Color.BLACK.getRGB() != 0xff000000) {
            throw new AssertionError("Standard colors changed");
        }
        float[] hsb = Color.RGBtoHSB(101, 177, 23, null);
        if (Color.HSBtoRGB(hsb[0], hsb[1], hsb[2]) != 0xff65b117) {
            throw new AssertionError("HSB conversion changed");
        }
        try {
            new Color(256, 0, 0);
            throw new AssertionError("Invalid component was accepted");
        } catch (IllegalArgumentException expected) { }
        if (!HintUtils.prepareText("for free", Color.GREEN).equals("<font color=#00ff00>for free</font>")
                || !HintUtils.prepareText("down to 6 cards", Color.YELLOW).equals("<font color=#ffff00>down to 6 cards</font>")
                || !HintUtils.prepareText("cost", Color.RED, HintUtils.HINT_ICON_BAD).equals("ICON_BAD<font color=#ff0000>cost</font>")
                || !HintUtils.colorToHtml(value).equals("#65b117")) {
            throw new AssertionError("Actual XMage colored prompt formatting changed");
        }
        long fingerprint = 0;
        for (int index = 0; index < 1024; index++) {
            int rgb = index * 0x21abcf;
            Color sample = new Color(rgb, true);
            Color floats = new Color(sample.getRed() / 255f, sample.getGreen() / 255f,
                    sample.getBlue() / 255f, sample.getAlpha() / 255f);
            if (!sample.equals(floats)) { throw new AssertionError("Float constructor changed"); }
            fingerprint = fingerprint * 31 + sample.brighter().getRGB();
            fingerprint = fingerprint * 31 + sample.darker().getRGB();
            fingerprint = fingerprint * 31 + sample.getTransparency();
        }
        System.out.println("PASS Color values and XMage hints: " + Long.toHexString(fingerprint));
        if (args.length == 1 && args[0].equals("--desktop-guard")) {
            try {
                Class.forName("java.awt.Toolkit", true, ColorValueProbe.class.getClassLoader());
                throw new AssertionError("Desktop Toolkit unexpectedly initialized successfully");
            } catch (UnsatisfiedLinkError expected) {
                if (!expected.getMessage().contains("no awt in java.library.path")) { throw expected; }
                System.out.println("PASS desktop Toolkit still fails explicitly without AWT");
            }
        }
    }
}
