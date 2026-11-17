import java.nio.file.Path;
import java.util.HashMap;
import java.util.Map;
import java.util.function.Function;
import zombie.core.Language;
import zombie.core.Translator;

public class CheckTranslations {
    public static void main(String[] args) throws Exception {
        var constructor = Language.class.getDeclaredConstructor(String.class, String.class, String.class, boolean.class);
        constructor.setAccessible(true);
        var language = constructor.newInstance("EN", "English", null, false);
        var loader = Translator.class.getDeclaredMethod("tryFillMapFromFile", String.class, String.class,
                Map.class, Language.class, Function.class);
        loader.setAccessible(true);
        Map<String, String> translations = new HashMap<>();
        loader.invoke(null, Path.of(args[0]).toAbsolutePath().toString(), "UI", translations,
                language, Function.identity());
        String key = "UI_WLM_Locale_PTBR_IGUI_WLM_ManagerSubtitle";
        if (!"Gerencie seus conjuntos de equipamento".equals(translations.get(key))) {
            throw new AssertionError("The PZ translation reader did not load the packaged PTBR UI text");
        }
        for (String code : new String[] {"EN", "ES", "FR", "DE", "IT", "PT", "PTBR", "RU", "CN", "UA", "KO", "JP", "TR"}) {
            String prefix = "UI_WLM_Locale_" + code + "_IGUI_WLM_";
            if (translations.get(prefix + "Title") == null || translations.get(prefix + "MissingCount") == null) {
                throw new AssertionError("Missing translations for " + code);
            }
        }
        Translator.getUI().putAll(translations);
        if (!translations.get(key).equals(Translator.getTextOrNull(key))) {
            throw new AssertionError("Native getTextOrNull did not return the packaged value");
        }
        for (String code : new String[] {"EN", "PTBR"}) {
            var selected = constructor.newInstance(code, code, null, false);
            for (String category : new String[] {"IGUI", "Sandbox"}) {
                Map<String, String> values = new HashMap<>();
                loader.invoke(null, Path.of(args[0]).toAbsolutePath().toString(), category,
                        values, selected, Function.identity());
                if (values.isEmpty()) {
                    throw new AssertionError("The native reader did not load " + code + "/" + category + ".json");
                }
            }
        }
        System.out.println("PASS: installed PZ JSON reader loaded " + translations.size()
                + " UI translations; native lookup returns PTBR; all 13 languages have UI text and placeholders.");
    }
}
