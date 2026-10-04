"""Exercise the offline exporter reader with a malformed provider cache fixture."""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime


class ProviderReaderTests(unittest.TestCase):
    def runtime(self, value="{982}", kind="number", field="breadcrumbForQuestId", name="Quest", cache=True):
        lua = LuaRuntime(unpack_returned_tuples=True)
        source = (Path(__file__).resolve().parents[1] / "tools/export_forever.lua").read_text()
        reader = source.split("local function row(db, name, id)", 1)[1].split(
            "local db, selectedFiles =", 1)[0]
        lua.execute("""
            calls, invalidations, executed = 0, 0, 0
            local cached = false
            db = { Meta = { """ + name + """ = {
                fieldCount=1, names={""" + repr(field) + """}, types={""" + repr(kind) + """}
            } }, """ + name + """ = {} }
            db.""" + name + """.Get = function(id, index)
                calls = calls + 1
                """ + ("if cached then return function() executed=executed+1; return 982 end end" if cache else "") + """
                cached = true
                return """ + value + """
            end
            db.""" + name + """.InvalidateCache = function(id)
                assert(id == 97894)
                invalidations = invalidations + 1
                cached = false
            end
        """)
        lua.execute("local function row(db, name, id)" + reader + "\n read = row")
        return lua

    def test_repeated_reads_recover_without_executing_cached_producer(self):
        lua = self.runtime()
        first = lua.globals().read(lua.globals().db, "Quest", 97894)
        second = lua.globals().read(lua.globals().db, "Quest", 97894)
        for result in (first, second):
            self.assertEqual(result.breadcrumbForQuestId, 982)
            audit = result._providerNormalizations.breadcrumbForQuestId
            self.assertEqual(audit.original[1], 982)
            self.assertEqual(audit.normalized, 982)
            self.assertEqual(audit.expectedType, "number")
        self.assertEqual(lua.globals().invalidations, 1)
        self.assertEqual(lua.globals().executed, 0)

    def test_valid_scalar_and_table_fields_keep_their_values(self):
        for value, kind, field in (("982", "number", "breadcrumbForQuestId"),
                                   ("{982,983}", "table", "preQuestGroup")):
            lua = self.runtime(value, kind, field, cache=False)
            row = lua.globals().read(lua.globals().db, "Quest", 97894)
            self.assertIsNone(row._providerNormalizations)
            self.assertEqual(row[field] if kind == "number" else row[field][2],
                             982 if kind == "number" else 983)

    def test_ambiguous_breadcrumb_values_fail_with_entity_and_field(self):
        for value in ("{}", "{982,983}", "{[2]=982}", "{982, extra=1}",
                      "{'982'}", "{0}", "{-982}", "{1.5}"):
            lua = self.runtime(value, cache=False)
            with self.subTest(value=value), self.assertRaisesRegex(Exception, "Quest/97894/breadcrumbForQuestId"):
                lua.globals().read(lua.globals().db, "Quest", 97894)

    def test_unrecoverable_function_is_rejected_without_execution(self):
        lua = self.runtime("function() executed=executed+1; return 982 end", cache=False)
        with self.assertRaisesRegex(Exception, "Quest/97894/breadcrumbForQuestId"):
            lua.globals().read(lua.globals().db, "Quest", 97894)
        self.assertEqual(lua.globals().executed, 0)


if __name__ == "__main__":
    unittest.main()
