import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import se.krka.kahlua.luaj.compiler.LuaCompiler;

public class CheckLua {
    public static void main(String[] args) throws Exception {
        String nativeName = "\u0420\u0443\u0441\u0441\u043a\u0438\u0439";
        var literal = LuaCompiler.loadstring("return \"" + nativeName + "\"", "unicode-check", null);
        if (nativeName.equals(literal.prototype.constants[0])) {
            throw new AssertionError("Expected the installed compiler's Unicode literal truncation");
        }
        int count = 0;
        try (var files = Files.walk(Path.of(args[0]))) {
            for (var path : files.filter(p -> p.toString().endsWith(".lua")).toList()) {
                LuaCompiler.loadstring(Files.readString(path, StandardCharsets.UTF_8), path.toString(), null);
                count++;
            }
        }
        System.out.println("PASS: reproduced Unicode literal truncation with the installed PZ compiler; compiled " + count + " Lua files.");
    }
}
