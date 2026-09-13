import java.awt.Color;
import mage.abilities.hint.HintUtils;

/** Native dependency regression only; not an XMage or iPhone gameplay test. */
public final class ColorValueProbe {
    public static void main(String[] args) {
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
        System.out.println("PASS pure Color values and actual XMage colored hints without a desktop toolkit");
    }
}
