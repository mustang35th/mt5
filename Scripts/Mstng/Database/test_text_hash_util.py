"""Run the shared text hash and both controller adapters on compatibility vectors.

Production MQL method bodies run through the existing C# adapter. Only the
string APIs and unchecked 64-bit arithmetic are supplied; this does not run MT5.
"""

import re
import unittest

from test_m5_observation_history_reader import ROOT, code_only, method, run_csharp


DIRECTORY = ROOT / "Include/Mstng/Indicator/ZigZagElliot"
CONTROLLERS = ("Mtf3In3AlertController", "Mtf3In3AlertAllController")
UTILITY = ROOT / "Include/Mstng/Util/TextHashUtil.mqh"
VECTORS = (
    ("", "14695981039346656037"),
    ("a", "12638187200555641996"),
    ("hello", "11831194018420276491"),
    ("foobar", "9625390261332436968"),
    ("値動き|M5|上昇", "12437138375244625796"),
    ("😀", "16565464328977483992"),
    ("EURUSD|M5|第3波|😀" * 2048, "6859211992857715493"),
)


def hash_class(source, class_name, method_name, static=False):
    """Keep the production loop, constants and decimal format unchanged."""
    body = method(source, method_name).replace("::", ".")
    modifier = "static " if static else ""
    return (
        f"public class {class_name} : MqlApi {{\n"
        f"public {modifier}string {method_name}(string fromText) {{\n"
        "unchecked {\n" + body + "\n}\n}\n}\n"
    )


def fixture(utility, controllers):
    source = r'''
using System;
using System.Globalization;
public class MqlApi {
    public static int StringLen(string value) { return value.Length; }
    public static ushort StringGetCharacter(string value, int index) { return value[index]; }
    public static string StringFormat(string format, ulong value) {
        if (format != "%I64u") { throw new ArgumentException("Unexpected hash format"); }
        return value.ToString(CultureInfo.InvariantCulture);
    }
}
'''
    source += hash_class(utility, "TextHashUtil", "createFnv1a64", static=True)
    for name, controller in controllers.items():
        source += hash_class(controller, name, "createTextHash")
    source += r'''
public class HashFixture {
    public static string Run(string text) {
        return TextHashUtil.createFnv1a64(text) + "|"
            + new Mtf3In3AlertController().createTextHash(text) + "|"
            + new Mtf3In3AlertAllController().createTextHash(text);
    }
}
'''
    return source


class TextHashUtilTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.controllers = {
            name: (DIRECTORY / (name + ".mqh")).read_text(encoding="utf-8-sig")
            for name in CONTROLLERS
        }
        utility = UTILITY.read_text(encoding="utf-8-sig")
        script = r'''
$inputs = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'input.json') -Raw | ConvertFrom-Json
foreach ($inputText in $inputs) { [HashFixture]::Run([string]$inputText) }
'''
        output = run_csharp(fixture(utility, cls.controllers), script,
                            [text for text, expected in VECTORS])
        cls.results = [line.split("|") for line in output.splitlines() if line.strip()]
        if len(cls.results) != len(VECTORS):
            raise AssertionError("Unexpected hash adapter output: " + output)

    def test_empty_and_known_ascii_vectors(self):
        for index in range(4):
            with self.subTest(text=VECTORS[index][0]):
                self.assertEqual(self.results[index][0], VECTORS[index][1])

    def test_japanese_and_surrogate_pair_use_utf16_units(self):
        for index in (4, 5):
            with self.subTest(text=VECTORS[index][0]):
                self.assertEqual(self.results[index][0], VECTORS[index][1])

    def test_long_input_wraps_and_returns_unsigned_decimal(self):
        self.assertEqual(self.results[6][0], VECTORS[6][1])
        self.assertGreater(int(self.results[0][0]), (1 << 63) - 1)
        for result in self.results:
            self.assertRegex(result[0], r"^[0-9]+$")
            self.assertLess(int(result[0]), 1 << 64)

    def test_both_controller_wrappers_preserve_database_hash(self):
        for index, (text, expected) in enumerate(VECTORS):
            with self.subTest(vector=index):
                self.assertEqual(self.results[index], [expected] * 3)
        for name, source in self.controllers.items():
            with self.subTest(controller=name):
                self.assertIn("#include <Mstng\\Util\\TextHashUtil.mqh>", source)
                wrapper = re.sub(r"\s+", "", code_only(method(source, "createTextHash")))
                self.assertEqual(wrapper, "returnTextHashUtil::createFnv1a64(fromText);")
                self.assertIn("this.databaseRun.inputHash=this.createTextHash(inputText);",
                              re.sub(r"\s+", "", code_only(source)))


if __name__ == "__main__":
    unittest.main()
