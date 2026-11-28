"""Exercise the production shared Elliott panel with a small MQL API substitute.

The syntax adapter preserves panel state and layout branches. Only MT5's chart
object API and font metrics are substituted; native compilation is checked
separately with MetaEditor.
"""

import re
import unittest

from test_m5_observation_history_reader import (
    ROOT, block_end, code_only, method, run_csharp, table_fixture, extracted_methods,
    table_layout_fixture, frame_fixture, strength_fixture, DRAWER, SAVED_ADAPTER,
    registry_fixture,
)


DRAW = ROOT / "Include/Mstng/Draw"


def syntax(source):
    """Adapt MQL scalar/reference/array syntax without changing branches."""
    source = re.sub(r"\bconst\s+", "", source)
    source = re.sub(r"\b(datetime|color|ENUM_ELLIOT_PANEL_ACTION|ENUM_TIMEFRAMES)\b",
                    lambda match: "long" if match[1] == "datetime" else "int", source)
    source = source.replace("::", ".").replace("NULL", "null")
    source = re.sub(r"\bDrawChartObjectRegistry\s*\*", "DrawChartObjectRegistry ", source)
    source = re.sub(r"\bdelete\s+(this\.\w+)\s*;", r"\1 = null;", source)
    source = re.sub(r"\b(\w+)\s*&\s*(\w+)", r"\1 \2", source)
    source = re.sub(r"\b(\w+)\s+(\w+)\[\]\s*=\s*\{", r"\1[] \2 = new \1[] {", source)
    source = re.sub(r"\b(string|int|double|bool|long|Elliot\w+|M5\w+)\s+(\w+)\[\]", r"\1[] \2", source)
    source = re.sub(r"\b(string|int|bool|long|double)\s+(\w+)\[(\d+)\]\s*;",
                    r"\1[] \2 = new \1[\3];", source)
    source = re.sub(r"C'(\d+),(\d+),(\d+)'",
                    lambda match: str(int(match[1]) + 256 * int(match[2]) + 65536 * int(match[3])), source)
    source = re.sub(r"\b(Elliot\w+)\s+(\w+)\s*;", r"\1 \2 = new \1();", source)
    source = re.sub(r"TextGetSize\(([^,]+),\s*(\w+),\s*(\w+)\)",
                    r"TextGetSize(\1, out \2, out \3)", source)
    return source


def scoped_class_fixture(source, name):
    """Keep scope batching logic; map MQL automatic destruction to IDisposable."""
    opening = re.search(r"\bclass " + name + r"\s*\{", source).end() - 1
    body = source[opening + 1:block_end(code_only(source), opening)]
    body = re.sub(r"\b(?:public|protected|private)\s*:", "", body)
    body = re.sub(r"~" + name + r"\s*\(\)", "void Dispose()", body)
    body = re.sub(r"\bDrawElliotPanel\s*\*", "DrawElliotPanel ", body)
    body = re.sub(r"\bDrawChartRedrawBatch\s+(\w+)\s*;",
                  r"DrawChartRedrawBatch \1 = new DrawChartRedrawBatch();", body)
    body = syntax(body)
    body = re.sub(r"^(\s{4})(?=(?:static\s+)?(?:bool|void|string|int|long|" + name + r")\b[^\n;=]*\()",
                  r"\1public ", body, flags=re.M)
    for kind, field, value in re.findall(r"\b(long|int|bool)\s+" + name + r"::(\w+)\s*=\s*([^;]+);", source):
        body = re.sub(r"\bstatic " + kind + " " + field + ";",
                      "static " + kind + " " + field + "=" + value + ";", body)
    return "public class " + name + " : MqlApi, IDisposable {\n" + body + "\n}\n"


def redraw_batch_fixture():
    source = (DRAW / "DrawChartRedrawBatch.mqh").read_text(encoding="utf-8-sig")
    return scoped_class_fixture(source, "DrawChartRedrawBatch")


def panel_data_fixture():
    source = (DRAW / "ElliotPanelData.mqh").read_text(encoding="utf-8-sig")
    result = []
    for found in re.finditer(r"\bstruct (\w+)\s*\{", source):
        name = found[1]
        body = source[found.end():block_end(code_only(source), found.end() - 1)]
        fields = re.findall(r"^\s*(\w+)\s+(\w+)(?:\[(\d+)\])?;", body, re.M)
        declaration = f"public class {name} : MqlApi {{\n"
        initialize = ""
        for kind, field, count in fields:
            adapted = "long" if kind == "datetime" else "int" if kind == "color" else kind
            complex_value = kind.startswith("Elliot")
            if count:
                declaration += f"public {adapted}[] {field}=new {adapted}[{count}];\n"
                if complex_value:
                    initialize += f"for(int i=0;i<{count};i++) {field}[i]=new {adapted}();\n"
            else:
                default = '=""' if kind == "string" else f"=new {adapted}()" if complex_value else ""
                declaration += f"public {adapted} {field}{default};\n"
        declaration += f"public {name}() {{ {initialize} clear(); }}\n"
        declaration += "public void clear() {" + syntax(method(body, "clear")) + "}\n}\n"
        result.append(declaration)
    return "\n".join(result)


def panel_layout_fixture():
    """Execute the production layout math independently of chart objects."""
    source = (DRAW / "ElliotPanelLayout.mqh").read_text(encoding="utf-8-sig")
    opening = re.search(r"\bclass ElliotPanelLayout\s*\{", source).end() - 1
    body = source[opening + 1:block_end(code_only(source), opening)]
    body = re.sub(r"\b(?:public|protected|private)\s*:", "", body)
    body = syntax(body)
    body = re.sub(r"^(\s{4})(?=(?:static\s+)?(?:bool|void|int|ElliotPanelLayout)\b[^\n;=]*\()",
                  r"\1public ", body, flags=re.M)
    body = re.sub(r"^(\s{4})((?:int|bool)(?:\[\])?\s+\w+(?:\s*=\s*[^;\n]+)?;)",
                  r"\1public \2", body, flags=re.M)
    return "public class ElliotPanelLayout : MqlApi {\n" + body + "\n}\n"


API = r'''
public class MqlApi {
    public const int PERIOD_CURRENT=0,PERIOD_M1=1,PERIOD_M5=5,PERIOD_M15=15,PERIOD_H1=16385,
        PERIOD_H4=16388,PERIOD_D1=16408,PERIOD_W1=32769,PERIOD_MN1=49153;
    public const int clrSilver=1,clrWhite=2,clrAqua=3,clrHotPink=4,clrDodgerBlue=5,clrMagenta=6,
        clrDeepSkyBlue=7,clrPlum=8,clrSlateGray=9,clrWhiteSmoke=10,clrGray=11,clrGold=12;
    public const int OBJ_LABEL=1,OBJ_RECTANGLE_LABEL=2,OBJ_BUTTON=3,CORNER_LEFT_UPPER=0,
        ANCHOR_LEFT_UPPER=0,ANCHOR_UPPER=1,BORDER_FLAT=0;
    public const int OBJPROP_CORNER=1,OBJPROP_ANCHOR=2,OBJPROP_XDISTANCE=3,OBJPROP_YDISTANCE=4,
        OBJPROP_COLOR=5,OBJPROP_FONTSIZE=6,OBJPROP_BACK=7,OBJPROP_SELECTABLE=8,OBJPROP_HIDDEN=9,
        OBJPROP_ZORDER=10,OBJPROP_FONT=11,OBJPROP_TEXT=12,OBJPROP_TOOLTIP=13,OBJPROP_XSIZE=14,
        OBJPROP_YSIZE=15,OBJPROP_BGCOLOR=16,OBJPROP_BORDER_TYPE=17,OBJPROP_SELECTED=18,
        OBJPROP_STATE=19,OBJPROP_BORDER_COLOR=20,OBJPROP_TIMEFRAMES=21;
    public const long OBJ_NO_PERIODS=0,OBJ_ALL_PERIODS=-1;
    public const int CHART_WIDTH_IN_PIXELS=1,CHART_HEIGHT_IN_PIXELS=2;
    public static int Width=1400,Height=800;
    public static long ChartID() { return 42; }
    public class ChartObject {
        public int kind;
        public long paintOrder;
        public bool visible=true;
        public Dictionary<int,long> numbers=new Dictionary<int,long>();
        public Dictionary<int,string> texts=new Dictionary<int,string>();
    }
    public static Dictionary<string,ChartObject> Objects=new Dictionary<string,ChartObject>();
    public static string FailName="",FailSuffix="";
    public static int CreateCalls,CreatedCount,DeleteCalls,DeletedCount,BulkDeleteCalls,SetIntegerCalls,SetStringCalls,RedrawCalls,DrawPasses,DrawPassesAtRedraw;
    public static List<string> Events=new List<string>();
    static long nextPaintOrder;
    public static void ResetCounts() {
        CreateCalls=CreatedCount=DeleteCalls=DeletedCount=BulkDeleteCalls=SetIntegerCalls=SetStringCalls=RedrawCalls=0;
        DrawPasses=DrawPassesAtRedraw=0;Events.Clear();
    }
    public static long ChartGetInteger(long chart,int property,int subwindow=0) {
        return property==CHART_WIDTH_IN_PIXELS ? Width : Height;
    }
    public static int ObjectFind(long chart,string name) { return Objects.ContainsKey(name) ? 0 : -1; }
    public static bool ObjectCreate(long chart,string name,int kind,int subwindow,long time,double price) {
        CreateCalls++;
        if(name==FailName || (FailSuffix.Length>0 && name.EndsWith(FailSuffix,StringComparison.Ordinal))) return false;
        if(!Objects.ContainsKey(name)) { Objects.Add(name,new ChartObject { kind=kind,paintOrder=++nextPaintOrder });CreatedCount++;Events.Add("create:"+name); }
        return true;
    }
    public static bool ObjectSetInteger(long chart,string name,int property,long value) {
        SetIntegerCalls++;
        if(property==OBJPROP_TIMEFRAMES) Events.Add((value==OBJ_NO_PERIODS ? "hide:" : "show:")+name);
        if(!Objects.ContainsKey(name)) return false;
        ChartObject item=Objects[name];
        if(property==OBJPROP_TIMEFRAMES) {
            bool visible=value!=OBJ_NO_PERIODS;
            // MT5 reintroduces a hidden object into the paint order when it
            // becomes visible; click priority (ZORDER) does not prevent cover.
            if(visible && !item.visible) item.paintOrder=++nextPaintOrder;
            item.visible=visible;
        }
        item.numbers[property]=value;return true;
    }
    public static bool ObjectSetInteger(long chart,string name,int property,bool value) {
        return ObjectSetInteger(chart,name,property,value ? 1L : 0L);
    }
    public static bool ObjectSetString(long chart,string name,int property,string value) {
        SetStringCalls++;
        if(!Objects.ContainsKey(name)) return false;Objects[name].texts[property]=value;return true;
    }
    public static int ObjectsDeleteAll(long chart,string prefix,int subwindow=0,int type=-1) {
        BulkDeleteCalls++;
        string[] names=Objects.Keys.Where(value=>value.StartsWith(prefix,StringComparison.Ordinal)).ToArray();
        foreach(string name in names) Objects.Remove(name);DeletedCount+=names.Length;return names.Length;
    }
    public static bool ObjectDelete(long chart,string name) {
        DeleteCalls++;bool removed=Objects.Remove(name);if(removed) { DeletedCount++;Events.Add("delete:"+name); }return removed;
    }
    public static void ChartRedraw(long chart=0) { RedrawCalls++;DrawPassesAtRedraw=DrawPasses;Events.Add("redraw"); }
    public static string[] CoveredTextNames(string prefix) {
        List<string> covered=new List<string>();
        foreach(KeyValuePair<string,ChartObject> pair in Objects) {
            ChartObject item=pair.Value;
            if(!pair.Key.StartsWith(prefix,StringComparison.Ordinal) || !item.visible || (item.kind!=OBJ_LABEL && item.kind!=OBJ_BUTTON)) continue;
            long x=item.numbers[OBJPROP_XDISTANCE],y=item.numbers[OBJPROP_YDISTANCE];
            if(item.kind==OBJ_BUTTON) { x+=item.numbers[OBJPROP_XSIZE]/2;y+=item.numbers[OBJPROP_YSIZE]/2; }
            else {
                if(item.numbers[OBJPROP_ANCHOR]!=ANCHOR_UPPER) x+=StringLen(item.texts[OBJPROP_TEXT])*4;
                y+=6;
            }
            foreach(ChartObject rectangle in Objects.Values) {
                if(!rectangle.visible || rectangle.kind!=OBJ_RECTANGLE_LABEL || rectangle.paintOrder<=item.paintOrder) continue;
                long left=rectangle.numbers[OBJPROP_XDISTANCE],top=rectangle.numbers[OBJPROP_YDISTANCE];
                long width=rectangle.numbers[OBJPROP_XSIZE],height=rectangle.numbers[OBJPROP_YSIZE];
                if(width>2 && height>2 && x>=left && x<left+width && y>=top && y<top+height) { covered.Add(pair.Key);break; }
            }
        }
        return covered.ToArray();
    }
    public static int MathMin(int first,int second) { return Math.Min(first,second); }
    public static int MathMax(int first,int second) { return Math.Max(first,second); }
    public static double MathMax(double first,double second) { return Math.Max(first,second); }
    public static int ArraySize<T>(T[] values) { return values.Length; }
    public static int ArrayResize<T>(ref T[] values,int length) { Array.Resize(ref values,length);return length; }
    public static void ArrayFree<T>(ref T[] values) { values=new T[0]; }
    public static int StringLen(string value) { return value==null ? 0 : value.Length; }
    public static int StringFind(string value,string needle) { return value.IndexOf(needle,StringComparison.Ordinal); }
    public static string StringSubstr(string value,int start,int count) { return value.Substring(start,count); }
    public static string StringSubstr(string value,int start) { return value.Substring(start); }
    public static long StringToInteger(string value) { return long.Parse(value,CultureInfo.InvariantCulture); }
    public static string IntegerToString(long value) { return value.ToString(CultureInfo.InvariantCulture); }
    public static string DoubleToString(double value,int digits) { return value.ToString("F"+digits,CultureInfo.InvariantCulture); }
    public static string StringFormat(string format,int value) {
        return format.Replace("%+d",value.ToString("+0;-0;+0",CultureInfo.InvariantCulture))
            .Replace("%d",IntegerToString(value));
    }
    public static string StringFormat(string format,double value) {
        return format.Replace("%.1f",DoubleToString(value,1)).Replace("%.2f",DoubleToString(value,2));
    }
    public static bool TextSetFont(string face,int size) { return true; }
    public static bool TextGetSize(string text,out uint width,out uint height) {
        width=(uint)StringLen(text)*8;height=12;return true;
    }
    public static T Clone<T>(T value) { return (T)CloneValue(value); }
    static object CloneValue(object value) {
        if(value==null) return null;
        Type type=value.GetType();
        if(type.IsValueType || type==typeof(string)) return value;
        Array array=value as Array;
        if(array!=null) {
            Array result=(Array)array.Clone();
            for(int i=0;i<array.Length;i++) result.SetValue(CloneValue(array.GetValue(i)),i);
            return result;
        }
        object copy=Activator.CreateInstance(type);
        foreach(System.Reflection.FieldInfo field in type.GetFields(System.Reflection.BindingFlags.Public|System.Reflection.BindingFlags.Instance))
            field.SetValue(copy,CloneValue(field.GetValue(value)));
        return copy;
    }
}
public class TimeUtil {
    public static string formatYyyymmddhhmiss(long value) {
        return new DateTime(1970,1,1).AddSeconds(value).ToString("yyyy/MM/dd HH:mm:ss",CultureInfo.InvariantCulture);
    }
}
'''


def panel_fixture():
    source = (DRAW / "DrawElliotPanel.mqh").read_text(encoding="utf-8-sig")
    opening = re.search(r"\bclass DrawElliotPanel\s*\{", source).end() - 1
    body = source[opening + 1:block_end(code_only(source), opening)]
    destructor = re.search(r"~DrawElliotPanel\s*\([^)]*\)\s*\{", body)
    if destructor:
        finish = block_end(code_only(body), destructor.end() - 1)
        body = body[:destructor.start()] + body[finish + 1:]
    body = re.sub(r"\b(?:public|protected|private)\s*:", "", body)
    body = syntax(body)
    body = re.sub(r"^(\s{4})(?=(?:static\s+)?(?:bool|void|string|int|long|DrawElliotPanel)\b[^\n;=]*\()",
                  r"\1public ", body, flags=re.M)
    # MQL DTO assignments copy values, including fixed arrays. C# fixture DTOs
    # are reference types, so clone only these assignment boundaries.
    body = re.sub(r"(this\.(?:liveData|savedData)\s*=\s*)(fromData)(\s*;)", r"\1Clone(\2)\3", body)
    # Count completed drawing passes at the header entry without replacing any
    # branch or chart-object operation in the production renderer.
    body = re.sub(r"(void drawHeader\([^)]*\)\s*\{)", r"\1 DrawPasses++;", body)
    enum_source = (DRAW / "ElliotPanelData.mqh").read_text(encoding="utf-8-sig") + source
    constants = []
    for enum in re.finditer(r"\benum ENUM_ELLIOT_PANEL_ACTION\s*\{([^}]+)\}", code_only(enum_source)):
        next_value = 0
        for item in enum[1].split(","):
            item = item.strip()
            if not item:
                continue
            parts = item.split("=")
            if len(parts) == 2:
                next_value = int(parts[1].strip())
            constants.append(f"public const int {parts[0].strip()}={next_value};")
            next_value += 1
    return "public class DrawElliotPanel : MqlApi {\n" + "\n".join(constants) + body + "\n}\n"


def table_renderer_fixture():
    source = (DRAW / "DrawElliotTable.mqh").read_text(encoding="utf-8-sig")
    names = re.findall(r"\bstatic\s+(?:string|bool|int)\s+(\w+)\s*\(", source)
    methods = syntax(extracted_methods(source, names))
    return table_layout_fixture(source) + "public class DrawElliotTable : MqlApi {\n" + methods + "}\n"


PANEL_SETUP = r'''
public class PanelFixture : MqlApi {
    static DrawElliotPanel ActivePanel=null;
    static string PanelName(string suffix) { return ActivePanel.getObjectPrefix()+suffix; }
    static int checks;
    static void Check(bool value,string message) { checks++;if(!value) throw new Exception(message); }
    static string Text(string name) { return Objects[name].texts[OBJPROP_TEXT]; }
    static long Number(string name,int property) { return Objects[name].numbers[property]; }
    static ElliotPanelData Data(string symbol,bool saved=false) {
        ElliotPanelData data=new ElliotPanelData { symbolName=symbol,digits=3,headerTime="JST 2026/11/25 12:00:00",
            savedTime=saved ? 1795500000L : 0L,rowCount=saved ? 7 : 8,canPrevious=saved,canNext=saved };
        int[] periods={PERIOD_MN1,PERIOD_W1,PERIOD_D1,PERIOD_H4,PERIOD_H1,PERIOD_M15,PERIOD_M5,PERIOD_M1};
        string[] labels={"MN1","W1","D1","H4","H1","M15","M5","M1"};
        for(int i=0;i<data.rowCount;i++) {
            ElliotPanelFrame frame=data.frames[i];frame.timeFrame=periods[i];
            frame.row.timeFrameLabel=labels[i];frame.row.hasData=true;frame.row.mainWave="3";
            frame.row.isBuy=1;frame.row.isUptrend=0;frame.row.isConfirmed=1;frame.row.isAdded=0;
            frame.row.originalWaveIndex=1;frame.row.hasPointRate=true;frame.row.pointRate=159.234;
            frame.row.hasPointPipsDiff=true;frame.row.pointPipsDiff=0;
            frame.pointTime=1795499700;frame.pointJstTime=1795524900;
            if(!saved) { frame.extraCount=1;frame.extraLabels[0]="SMO";frame.extraValues[0]="+2"; }
        }
        data.strength.enabled=true;data.strength.status="";data.strength.title=saved ? "同M5の通貨強弱履歴" : "現在の通貨強弱";
        data.strength.baseCurrency="USD";data.strength.quoteCurrency="JPY";
        data.strength.longMedium.valid=true;data.strength.longMedium.baseRank=2;data.strength.longMedium.quoteRank=7;
        data.strength.longMedium.gap=5;data.strength.longMedium.comparable=true;data.strength.longMedium.delta=-2;
        return data;
    }
'''


def run_panel_csharp(source, script):
    """Resolve fixture labels against the production panel's active generation."""
    start = source.index("public class PanelFixture : MqlApi")
    body = source[start:]
    body = body.replace('DrawElliotPanel panel=new DrawElliotPanel(0,"Panel-");',
                        'DrawElliotPanel panel=new DrawElliotPanel(0,"Panel-");ActivePanel=panel;')
    body = re.sub(r'"Panel-([^"\r\n]+)"', r'PanelName("\1")', body)
    return run_csharp(source[:start] + body, script)


class ElliotPanelViewTests(unittest.TestCase):
    def layout_source(self):
        return ("using System;using System.Globalization;using System.Collections.Generic;using System.Linq;\n"
                + API + panel_layout_fixture())

    def panel_source(self):
        return ("using System;using System.Globalization;using System.Collections.Generic;using System.Linq;\n"
                + API + registry_fixture() + table_fixture() + panel_data_fixture() + table_renderer_fixture()
                + panel_layout_fixture() + panel_fixture())

    def test_layout_size_and_column_boundaries_without_chart_objects(self):
        source = self.layout_source() + r'''
public class LayoutFixture : MqlApi {
    static int checks;
    static void Check(bool value,string message) { checks++;if(!value) throw new Exception(message); }
    public static string Run() {
        ElliotPanelLayout layout=new ElliotPanelLayout();ResetCounts();
        Check(!layout.setChartSize(183,800),"chart width 183 leaves less than the minimum panel width");
        Check(!layout.setChartSize(184,103),"chart height 103 leaves less than the minimum available height");
        Check(layout.setChartSize(184,104),"minimum chart dimensions accept a 160 by 80 available panel");
        layout.calculate(8,true,0,false);
        Check(layout.panelLeft==12 && layout.panelTop==12 && layout.panelWidth==160 && layout.panelHeight==80 && !layout.showTable,"minimum panel bounds and hidden table");
        foreach(int width in new int[]{639,640,759,760,959,960}) {
            Check(layout.setChartSize(width+24,1000),"valid chart width "+width);
            layout.calculate(8,true,0,true);
            Check(layout.panelWidth==width && layout.showTable==(width>=640) && layout.showDetails==(width>=640),"640-pixel list and details threshold: "+width);
            Check(layout.headerHeight==(width<760 ? 104 : 80),"760-pixel header threshold: "+width);
            Check(layout.detailColumns==(width<960 ? 2 : 3),"960-pixel detail column threshold: "+width);
            Check(layout.contentLeft==24 && layout.contentWidth==width-24,"content retains inner margins: "+width);
            int[] positions={0,64,128,192,400};int[] widths={64,64,64,96,width-424};
            for(int i=0;i<5;i++) Check(layout.columnXs[i]==positions[i] && layout.columnWidths[i]==widths[i],"stable column boundary "+width+"/"+i);
            Check(layout.gmmaColumnXs[0]==288 && layout.gmmaColumnXs[1]==344 && layout.gmmaColumnWidths[0]==56 && layout.gmmaColumnWidths[1]==56,"GMMA columns remain between movement and Elliot");
        }
        layout.setChartSize(1400,1000);layout.calculate(8,true,0,false);
        Check(layout.panelWidth==960 && layout.panelHeight==342 && layout.tableTop==92 && layout.hintTop==334,"maximum width and eight-row collapsed panel geometry");
        Check(CreateCalls==0 && DeleteCalls==0 && BulkDeleteCalls==0 && SetIntegerCalls==0 && SetStringCalls==0 && RedrawCalls==0,"layout calculations have no chart-object side effects");
        return "PASS "+checks+" layout size assertions";
    }
}
'''
        self.assertRegex(run_csharp(source, "[LayoutFixture]::Run()\n"), r"PASS \d+ layout size assertions")

    def test_layout_height_boundaries_and_reused_result_clear_details(self):
        source = self.layout_source() + r'''
public class LayoutFixture : MqlApi {
    static int checks;
    static void Check(bool value,string message) { checks++;if(!value) throw new Exception(message); }
    public static string Run() {
        ElliotPanelLayout layout=new ElliotPanelLayout();
        layout.setChartSize(984,564);layout.calculate(8,true,0,true);
        Check(layout.showDetails && layout.rowHeight==24 && layout.detailRowHeight==22 && layout.panelHeight==540,"full-height details fit exactly");
        Check(layout.detailTop==336 && layout.strengthTop==448 && layout.extrasTop==524,"details and strength retain their full-height positions");
        layout.setChartSize(984,563);layout.calculate(8,true,0,true);
        Check(layout.showDetails && layout.rowHeight==20 && layout.detailRowHeight==18 && layout.panelHeight==480,"one pixel less switches to compressed rows");
        Check(layout.detailTop==300 && layout.strengthTop==396 && layout.extrasTop==472,"compressed details and strength positions");
        layout.setChartSize(984,504);layout.calculate(8,true,0,true);
        Check(layout.showDetails && layout.panelHeight==480,"compressed details fit exactly");
        layout.setChartSize(984,503);layout.calculate(8,true,0,true);
        Check(!layout.showDetails && layout.showTable && layout.panelHeight==306,"below compressed-detail threshold returns to list only");
        layout.setChartSize(984,364);layout.calculate(8,true,0,false);
        Check(layout.showTable && layout.panelHeight==340,"table may fit two pixels below desired list height");
        layout.setChartSize(984,363);layout.calculate(8,true,0,false);
        Check(!layout.showTable,"one pixel below required list height hides table");
        layout.setChartSize(984,650);layout.calculate(8,true,8,true);
        Check(layout.showDetails && layout.rowHeight==24 && layout.panelHeight==626 && layout.extraCount==8,"eight extras reserve three detail rows at full width");
        layout.setChartSize(983,716);layout.calculate(8,true,8,true);
        Check(layout.showDetails && layout.rowHeight==24 && layout.panelHeight==692 && layout.detailColumns==2,"eight extras reserve four rows below full width");
        layout.setChartSize(984,540);layout.calculate(7,true,0,true);
        Check(layout.showDetails && layout.rowHeight==24 && layout.panelHeight==516,"seven saved rows fit at their own boundary");
        layout.setChartSize(984,180);layout.calculate(0,false,0,true);
        Check(layout.rowCount==0 && !layout.showTable && !layout.showDetails && layout.rowHeight==20 && layout.extraCount==0 && layout.panelHeight==146,"empty expanded data still uses legacy compression and clears prior detail state");
        layout.setChartSize(984,1000);layout.calculate(-1,false,0,false);
        Check(layout.rowCount==0 && !layout.showTable && !layout.showDetails,"negative row count clamps to zero");
        layout.calculate(99,true,99,true);
        Check(layout.rowCount==8 && layout.extraCount==8 && layout.showTable && layout.showDetails && layout.rowHeight==24,"reusing layout restores full geometry and clamps capacities");
        return "PASS "+checks+" layout height assertions";
    }
}
'''
        self.assertRegex(run_csharp(source, "[LayoutFixture]::Run()\n"), r"PASS \d+ layout height assertions")

    def test_tiny_chart_keeps_selection_until_layout_can_be_drawn(self):
        source = self.panel_source() + PANEL_SETUP + r'''
    public static string Run() {
        DrawElliotPanel panel=new DrawElliotPanel(0,"Panel-");
        ElliotPanelData live=Data("USDJPY");panel.updateLive(live);
        panel.onObjectClick("Panel-Row1-TimeFrame");
        Check(panel.getSelectedTimeFrame()==PERIOD_M1,"current M1 row can be selected");
        Width=183;ElliotPanelData saved=Data("USDJPY",true);
        Check(!panel.showSaved(saved) && panel.getSelectedTimeFrame()==PERIOD_M1,"too narrow chart defers saved-row fallback");
        Check(Objects.Count==0 && !panel.containsPoint(20,20),"too narrow chart clears its frame and hover bounds");
        Width=1400;Height=103;
        Check(!panel.draw() && panel.getSelectedTimeFrame()==PERIOD_M1,"too short chart also preserves selection");
        Height=800;Check(panel.draw(),"restoring chart dimensions renders saved data");
        Check(panel.getSelectedTimeFrame()==PERIOD_M5 && Objects.ContainsKey("Panel-Row5-TimeFrame"),"saved M5 fallback occurs only once layout is drawable");
        return "PASS "+checks+" tiny-chart selection assertions";
    }
}
'''
        self.assertRegex(run_panel_csharp(source, "[PanelFixture]::Run()\n"), r"PASS \d+ tiny-chart selection assertions")

    def test_nested_batches_flush_latest_panel_once_before_one_chart_redraw(self):
        controller = (ROOT / "Include/Mstng/Indicator/ZigZagElliot/ZigZagElliotController.mqh").read_text(encoding="utf-8-sig")
        source = (self.panel_source() + redraw_batch_fixture()
                  + scoped_class_fixture(controller, "ZigZagElliotDrawBatch") + PANEL_SETUP + r'''
    public static string Run() {
        DrawElliotPanel panel=new DrawElliotPanel(0,"Panel-");ElliotPanelData data=Data("USDJPY");
        panel.updateLive(data);ResetCounts();
        using(ZigZagElliotDrawBatch outer=new ZigZagElliotDrawBatch(panel)) {
            data.frames[6].row.mainWave="4";panel.updateLive(data);panel.draw();DrawChartRedrawBatch.request();
            using(ZigZagElliotDrawBatch inner=new ZigZagElliotDrawBatch(panel)) {
                data.frames[6].row.mainWave="5";panel.updateLive(data);panel.draw();DrawChartRedrawBatch.request(42);
                Check(DrawPasses==0 && RedrawCalls==0 && Text("Panel-Row5-ElliotMainWave")=="3","nested requests defer object updates and chart redraw");
            }
            Check(DrawPasses==0 && RedrawCalls==0,"inner scope cannot flush the outer event");
            outer.finish();
            Check(DrawPasses==1 && RedrawCalls==1 && DrawPassesAtRedraw==1,"outer event renders once before one chart redraw");
            Check(Text("Panel-Row5-ElliotMainWave")=="5" && CreatedCount==0 && DeletedCount==0,"one flush applies the latest queued values without recreating objects");
            outer.finish();
            Check(DrawPasses==1 && RedrawCalls==1,"explicit finish is idempotent");
        }
        Check(DrawPasses==1 && RedrawCalls==1,"destruction after explicit finish does not redraw again");
        ResetCounts();EarlyReturn(panel);
        Check(DrawPasses==1 && RedrawCalls==1 && DrawPassesAtRedraw==1,"early return flushes pending panel and redraw requests in order");
        ResetCounts();using(ZigZagElliotDrawBatch empty=new ZigZagElliotDrawBatch(panel)) {}
        Check(DrawPasses==0 && RedrawCalls==0,"an event without changes performs no rendering");
        ResetCounts();using(DrawChartRedrawBatch batch=new DrawChartRedrawBatch()) {
            DrawChartRedrawBatch.request(99);Check(RedrawCalls==1,"other chart redraw is independent of this chart batch");
            DrawChartRedrawBatch.request();DrawChartRedrawBatch.request(42);
        }
        Check(RedrawCalls==2,"same chart alias zero and concrete id share one redraw");
        return "PASS "+checks+" draw batching assertions";
    }
    static void EarlyReturn(DrawElliotPanel panel) {
        using(ZigZagElliotDrawBatch batch=new ZigZagElliotDrawBatch(panel)) {
            panel.draw();panel.draw();DrawChartRedrawBatch.request();return;
        }
    }
}
''')
        self.assertRegex(run_panel_csharp(source, "[PanelFixture]::Run()\n"), r"PASS \d+ draw batching assertions")

    def test_controller_event_routes_coalesce_duplicate_panel_and_redraw_requests(self):
        controller = (ROOT / "Include/Mstng/Indicator/ZigZagElliot/ZigZagElliotController.mqh").read_text(encoding="utf-8-sig")
        body = syntax(method(controller, "onChartEvent"))
        body = re.sub(r"\bElliotAll\s*\*", "ElliotAll ", body)
        body = re.sub(r"\bELLIOT_PANEL_ACTION_(\w+)\b", r"DrawElliotPanel.ELLIOT_PANEL_ACTION_\1", body)
        body = body.replace("ulong startMicroseconds", "ulong chartStartMicroseconds", 1)
        body = body.replace("completeSlowOperation(stageChartEvent, startMicroseconds)",
                            "completeSlowOperation(stageChartEvent, chartStartMicroseconds)", 1)
        body = body.replace("ZigZagElliotDrawBatch drawBatch(this.elliotPanel);",
                            "using(ZigZagElliotDrawBatch drawBatch=new ZigZagElliotDrawBatch(this.elliotPanel)) {") + "}"
        source = (self.panel_source() + redraw_batch_fixture()
                  + scoped_class_fixture(controller, "ZigZagElliotDrawBatch") + r'''
public class ElliotAll {}
public class EventDependency : MqlApi {
    public DrawElliotPanel panel;public ElliotPanelData saved;
    public void redraw() { panel.draw();panel.draw();DrawChartRedrawBatch.request(); }
    public void onMouseMove(int x,int y) { DrawChartRedrawBatch.request(); }
    public void handleMouseMove(int x,int y,object history) { DrawChartRedrawBatch.request(); }
    public void syncElliotPanelState() { panel.draw(); }
    public void navigatePanel(int direction) { saved.savedTime+=direction*300;panel.showSaved(saved);redraw(); }
    public bool onObjectClick(string name) { if(name!="Marker") return false;panel.showSaved(saved);redraw();return true; }
    public bool onObjectClick(string name,ElliotAll data) { redraw();return true; }
    public bool onChartChange(ElliotAll data) { redraw();return true; }
    public void update(bool changed) { redraw(); }
    public void reposition() { DrawChartRedrawBatch.request(); }
    public ulong startSlowOperation() { return 1; }
    public void completeSlowOperation(string name,ulong started) {}
    public ElliotAll getElliotAll() { return new ElliotAll(); }
}
public class EventFixture : MqlApi {
    public const int CHARTEVENT_MOUSE_MOVE=1,CHARTEVENT_OBJECT_CLICK=2,CHARTEVENT_CHART_CHANGE=3;
    const string stageChartEvent="event";
    DrawElliotPanel elliotPanel;
    EventDependency rankDeltaRibbon,m5ObservationDisplayController,chartController,analysisController,currencyStrengthController;
    object rankDeltaBandHistory=null,databaseAlertDisplayController=new object();
    public EventFixture(DrawElliotPanel panel,ElliotPanelData saved) {
        elliotPanel=panel;EventDependency dependency=new EventDependency { panel=panel,saved=saved };
        rankDeltaRibbon=m5ObservationDisplayController=chartController=analysisController=currencyStrengthController=dependency;
    }
    void prepareDatabaseAlertDisplay() {}
    void beginCurrencyStrengthRedrawBatch() {}
    void endCurrencyStrengthRedrawBatch() {}
    void drawRankDeltaBand() { DrawChartRedrawBatch.request(); }
    void completeRedraw() { elliotPanel.draw();DrawChartRedrawBatch.request(); }
    public void onChartEvent(int fromId,string fromObjectName,int fromMouseX=0,int fromMouseY=0) {
''' + body + "}\n}\n" + PANEL_SETUP + r'''
    public static string Run() {
        DrawElliotPanel panel=new DrawElliotPanel(0,"Panel-");panel.updateLive(Data("USDJPY"));
        EventFixture controller=new EventFixture(panel,Data("SAVED",true));
        ResetCounts();controller.onChartEvent(EventFixture.CHARTEVENT_OBJECT_CLICK,"Panel-Row15-GmmaTrend");
        Check(DrawPasses==1 && RedrawCalls==1 && DrawPassesAtRedraw==1,"panel click merges panel, history and sync redraw requests before early return");
        Check(panel.getSelectedTimeFrame()==PERIOD_M15 && panel.isExpanded(),"coalesced click preserves selected timeframe and expansion");
        ResetCounts();controller.onChartEvent(EventFixture.CHARTEVENT_OBJECT_CLICK,"Marker");
        Check(DrawPasses==1 && RedrawCalls==1 && panel.isSavedMode(),"saved marker branch flushes once despite multiple lower-level requests");
        long savedTime=panel.getSavedTime();
        ResetCounts();controller.onChartEvent(EventFixture.CHARTEVENT_OBJECT_CLICK,"Panel-Previous");
        Check(DrawPasses==1 && RedrawCalls==1 && panel.getSavedTime()==savedTime-300,"previous navigation updates saved snapshot in one drawing pass");
        ResetCounts();controller.onChartEvent(EventFixture.CHARTEVENT_CHART_CHANGE,"");
        Check(DrawPasses==1 && RedrawCalls==1 && DrawPassesAtRedraw==1,"chart resize coalesces history, strength and complete redraw into one final pass");
        ResetCounts();controller.onChartEvent(EventFixture.CHARTEVENT_MOUSE_MOVE,"",20,30);
        Check(DrawPasses==0 && RedrawCalls==1,"two hover redraw requests merge without drawing the unchanged panel");
        ResetCounts();controller.onChartEvent(99,"");
        Check(DrawPasses==0 && RedrawCalls==0,"unhandled event does not flush nonexistent work");
        return "PASS "+checks+" event batching assertions";
    }
}
''')
        self.assertRegex(run_panel_csharp(source, "[PanelFixture]::Run()\n"), r"PASS \d+ event batching assertions")

    def test_repeated_updates_reuse_objects_and_restore_missing_or_failed_cells(self):
        source = self.panel_source() + PANEL_SETUP + r'''
    public static string Run() {
        DrawElliotPanel panel=new DrawElliotPanel(0,"Panel-");
        ElliotPanelData live=Data("USDJPY");
        live.frames[6].row.hasGmmaTrendCount=true;live.frames[6].row.gmmaTrendCount=4;
        Check(panel.updateLive(live),"initial current view draws successfully");
        int objectCount=Objects.Count;
        Dictionary<string,ChartObject> initial=new Dictionary<string,ChartObject>(Objects);
        ResetCounts();Check(panel.updateLive(live),"same current snapshot refresh succeeds");
        Check(CreateCalls==0 && CreatedCount==0 && DeleteCalls==0 && DeletedCount==0 && BulkDeleteCalls==0,"same layout refresh issues no creation or deletion calls");
        Check(Objects.Count==objectCount && initial.All(pair=>Object.ReferenceEquals(pair.Value,Objects[pair.Key])),"same layout preserves every object identity");
        int unchangedSetCalls=SetIntegerCalls+SetStringCalls;
        live.frames[6].row.mainWave="5";live.frames[6].row.gmmaTrendCount=-7;live.headerTime="JST 2026/11/25 12:01:00";
        ResetCounts();Check(panel.updateLive(live),"changed current snapshot refresh succeeds");
        Check(CreatedCount==0 && DeletedCount==0 && Objects.Count==objectCount,"value and color updates retain the same objects");
        Check(Text("Panel-Row5-ElliotMainWave")=="5" && Text("Panel-Row5-GmmaTrend")=="-7" && Number("Panel-Row5-GmmaTrend",OBJPROP_COLOR)==clrHotPink,"reused cells update value and sign color");
        Check(Text("Panel-Time")==live.headerTime && Objects["Panel-Row5-GmmaTrend"].texts[OBJPROP_TOOLTIP].Contains("-7"),"reused time and tooltip properties refresh with the snapshot");
        ObjectDelete(0,"Panel-Row5-GmmaTrend");
        ResetCounts();Check(panel.draw(),"externally deleted cell is restored");
        Check(CreatedCount==1 && DeletedCount==0 && Text("Panel-Row5-GmmaTrend")=="-7","external deletion recreates only the missing cell with current value");
        Check(Object.ReferenceEquals(initial["Panel-Background"],Objects["Panel-Background"]),"external cell recovery retains the original frame");
        ObjectDelete(0,"Panel-Row5-ElliotPrice");FailName="Panel-Row5-ElliotPrice";
        ResetCounts();Check(!panel.draw(),"failed replacement is reported");
        Check(!Objects.ContainsKey(FailName) && Objects.ContainsKey("Panel-Row1-ElliotPrice") && DeletedCount==0,"one failed cell does not remove the remaining table");
        FailName="";ResetCounts();Check(panel.draw(),"later refresh recovers failed replacement");
        Check(CreatedCount==1 && DeletedCount==0 && Text("Panel-Row5-ElliotPrice")=="159.234","recovery creates only the missing cell");
        panel.clear();FailName="Panel-Title";ResetCounts();
        Check(!panel.draw() && Objects.ContainsKey("Panel-Close") && !Objects.ContainsKey("Panel-Title"),"partial initial drawing failure leaves usable controls");
        ChartObject partialFrame=Objects["Panel-Background"];
        FailName="";ResetCounts();Check(panel.draw(),"initial failure retries successfully");
        Check(CreatedCount==1 && DeletedCount==0 && Object.ReferenceEquals(partialFrame,Objects["Panel-Background"]),"initial failure recovery preserves objects already created");
        ObjectDelete(0,"Panel-Row1-ElliotPrice");FailName="Panel-Row1-ElliotPrice";
        Check(!panel.draw(),"a cell can fail before its timeframe becomes absent");
        FailName="";live.rowCount=7;
        Check(panel.updateLive(live) && !Objects.ContainsKey("Panel-Row1-ElliotPrice"),"uncreated stale cell is discarded without an endless deletion failure");
        ResetCounts();Check(panel.draw() && CreatedCount==0 && DeletedCount==0,"failed then absent cell does not leave repeated cleanup work");
        return "PASS "+checks+" reuse assertions; objects="+objectCount+"; same-layout create=0 delete=0; unchanged property sets="+unchangedSetCalls;
    }
}
'''
        self.assertRegex(run_panel_csharp(source, "[PanelFixture]::Run()\n"), r"PASS \d+ reuse assertions; objects=\d+; same-layout create=0 delete=0")

    def test_front_generation_is_published_before_retiring_old_view_and_failed_generation_recovers(self):
        source = self.panel_source() + PANEL_SETUP + r'''
    public static string Run() {
        DrawElliotPanel panel=new DrawElliotPanel(0,"Panel-");panel.updateLive(Data("USDJPY"));
        panel.onObjectClick("Panel-Row15-GmmaTrend");
        Check(CoveredTextNames(panel.getObjectPrefix()).Length==0,"initial labels and controls are visible above their backgrounds");
        string oldPrefix=panel.getObjectPrefix();
        Dictionary<string,ChartObject> original=new Dictionary<string,ChartObject>(Objects);
        int count=Objects.Count;ResetCounts();
        panel.beginDrawBatch();panel.requestBringToFront();panel.requestBringToFront();
        Check(CreatedCount==0 && DeletedCount==0,"front requests wait for the event boundary");
        Check(panel.endDrawBatch(),"completed replacement generation is published");
        string prefix=panel.getObjectPrefix();
        Check(prefix!=oldPrefix && CreatedCount==count && DeletedCount==count && DrawPasses==1,"multiple front requests build and retire one complete generation");
        Check(Objects.Count==count && Objects.Keys.All(name=>name.StartsWith(prefix,StringComparison.Ordinal)),"successful replacement leaves no prior generation objects");
        string[] created=Events.Where(item=>item.StartsWith("create:",StringComparison.Ordinal)).Select(item=>item.Substring(7)).ToArray();
        string[] shown=Events.Where(item=>item.StartsWith("show:",StringComparison.Ordinal)).Select(item=>item.Substring(5)).ToArray();
        Check(created.SequenceEqual(shown),"new objects become visible in creation order with backgrounds before their contents");
        Check(CoveredTextNames(prefix).Length==0,"published generation has no labels or controls covered by later-visible opaque rectangles");
        int firstShow=Events.FindIndex(item=>item.StartsWith("show:",StringComparison.Ordinal));
        int lastShow=Events.FindLastIndex(item=>item.StartsWith("show:",StringComparison.Ordinal));
        int firstDelete=Events.FindIndex(item=>item.StartsWith("delete:",StringComparison.Ordinal));
        Check(created.All(name=>Events.IndexOf("hide:"+name)>=0 && Events.IndexOf("hide:"+name)<firstShow),"every replacement object is hidden while the new generation is built");
        Check(firstDelete>lastShow && !original.Keys.Any(name=>Events.Contains("hide:"+name)),"the old generation stays visible until every replacement is published");
        Check(panel.getSelectedTimeFrame()==PERIOD_M15 && panel.isExpanded() && Text("Panel-DetailTitle")=="M15 の詳細","front generation preserves selected details");
        original=new Dictionary<string,ChartObject>(Objects);oldPrefix=panel.getObjectPrefix();
        FailSuffix="Row5-ElliotPrice";ResetCounts();
        Check(!panel.requestBringToFront(),"a mid-generation creation failure is reported");
        Check(panel.getObjectPrefix()==oldPrefix && Objects.Count==count && original.All(pair=>Objects.ContainsKey(pair.Key)&&Object.ReferenceEquals(pair.Value,Objects[pair.Key])),"failed replacement leaves the complete original generation intact");
        Check(!Events.Any(item=>item.StartsWith("show:",StringComparison.Ordinal)) && original.Keys.All(name=>!Events.Contains("delete:"+name)),"an incomplete generation is never published and never retires the visible generation");
        FailSuffix="";ResetCounts();Check(panel.draw(),"pending replacement retries after the failure clears");
        Check(panel.getObjectPrefix()!=oldPrefix && Objects.Count==count && CreatedCount==count && DeletedCount==count,"retry replaces the view once without leftover failed objects");
        oldPrefix=panel.getObjectPrefix();ObjectDelete(0,"Panel-Background");ResetCounts();
        Check(panel.draw() && panel.getObjectPrefix()!=oldPrefix,"externally deleted background triggers a complete layer-safe rebuild");
        Check(Objects.Count==count && CreatedCount==count && DeletedCount==count-1,"background recovery rebuilds the complete view and retires every surviving old object");
        Check(CoveredTextNames(panel.getObjectPrefix()).Length==0,"background recovery leaves all contents visible");
        ObjectSetInteger(0,"Panel-Background",OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
        ObjectSetInteger(0,"Panel-Background",OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
        Check(CoveredTextNames(panel.getObjectPrefix()).Length>0,"fixture detects the observed regression when an opaque background is made visible last");
        Check(panel.requestBringToFront() && CoveredTextNames(panel.getObjectPrefix()).Length==0,"production generation order restores visible contents after the reproduced layering failure");
        return "PASS "+checks+" generation assertions";
    }
}
'''
        self.assertRegex(run_panel_csharp(source, "[PanelFixture]::Run()\n"), r"PASS \d+ generation assertions")

    def test_structure_changes_delete_only_stale_owned_objects_and_keep_cached_selection(self):
        source = self.panel_source() + PANEL_SETUP + r'''
    public static string Run() {
        DrawElliotPanel panel=new DrawElliotPanel(0,"Panel-");ElliotPanelData live=Data("USDJPY");
        panel.updateLive(live);ChartObject frame=Objects["Panel-Background"],close=Objects["Panel-Close"];
        ObjectCreate(0,"Other-Label",OBJ_LABEL,0,0,0);
        panel.onObjectClick("Panel-Row15-GmmaTrend");
        Check(panel.isExpanded() && Text("Panel-DetailTitle")=="M15 の詳細","row click expands reusable details");
        ResetCounts();panel.setExpanded(false);
        Check(DeletedCount>0 && !Objects.ContainsKey("Panel-DetailTitle") && !Objects.ContainsKey("Panel-ExtraTitle"),"collapse removes details and extras that are no longer drawn");
        Check(Objects.ContainsKey("Panel-Background") && Objects.ContainsKey("Panel-Close"),"collapse keeps a complete frame and controls");
        ObjectDelete(0,"Panel-Row1-TimeFrame");
        ElliotPanelData saved=Data("HISTORY",true);Check(panel.showSaved(saved),"already removed stale cell does not make mode transition fail");
        Check(panel.isSavedMode() && panel.getSelectedTimeFrame()==PERIOD_M15 && !Objects.ContainsKey("Panel-Row1-TimeFrame"),"saved transition removes only absent M1 while retaining selection");
        Check(!Objects.ContainsKey("Panel-ExtraTitle") && Objects.ContainsKey("Panel-Live") && Objects.ContainsKey("Panel-Previous"),"saved transition replaces current-only extras with history controls");
        ChartObject savedWave=Objects["Panel-Row5-ElliotMainWave"];
        live.frames[6].row.mainWave="5";ResetCounts();panel.updateLive(live);
        Check(CreatedCount==0 && DeletedCount==0 && Text("Panel-Row5-ElliotMainWave")=="3" && Object.ReferenceEquals(savedWave,Objects["Panel-Row5-ElliotMainWave"]),"background current update leaves saved objects untouched");
        panel.showLive();
        Check(!panel.isSavedMode() && panel.getSelectedTimeFrame()==PERIOD_M15 && Text("Panel-Row5-ElliotMainWave")=="5","return uses latest current cache and preserves timeframe");
        Check(Objects.ContainsKey("Panel-Row1-TimeFrame") && !Objects.ContainsKey("Panel-Live") && !Objects.ContainsKey("Panel-Previous") && !Objects.ContainsKey("Panel-Next"),"return creates M1 and removes stale saved controls");
        Width=983;panel.draw();
        Check(Objects.ContainsKey("Panel-Row5-Elliot") && !Objects.ContainsKey("Panel-Row5-ElliotMainWave") && !Objects.ContainsKey("Panel-HeaderGroupElliot"),"narrow view removes all obsolete split labels and group heading");
        Check(!Objects.Keys.Any(name=>name.StartsWith("Panel-Row5-ElliotLine",StringComparison.Ordinal)),"narrow view removes split separators too");
        Width=984;panel.draw();
        Check(!Objects.ContainsKey("Panel-Row5-Elliot") && Objects.ContainsKey("Panel-Row5-ElliotMainWave"),"wide view removes obsolete composite cell");
        live.rowCount=0;live.status="準備待ち";panel.updateLive(live);
        Check(Objects.ContainsKey("Panel-Empty") && !Objects.Keys.Any(name=>name.StartsWith("Panel-Row",StringComparison.Ordinal)||name.StartsWith("Panel-Header",StringComparison.Ordinal)),"empty view removes all stale rows and table headers");
        Check(Objects.ContainsKey("Panel-Background") && Objects.ContainsKey("Other-Label"),"every structure change retains a frame and unrelated chart objects");
        panel.onObjectClick("Panel-Close");
        Check(!Objects.Keys.Any(name=>name.StartsWith("Panel-",StringComparison.Ordinal)) && Objects.ContainsKey("Other-Label"),"close removes only panel-owned objects");
        ResetCounts();panel.updateLive(Data("NEW"));
        Check(!panel.isVisible() && CreatedCount==0 && DeletedCount==0,"closed panel stays closed during background updates");
        return "PASS "+checks+" stale object assertions";
    }
}
'''
        self.assertRegex(run_panel_csharp(source, "[PanelFixture]::Run()\n"), r"PASS \d+ stale object assertions")

    def test_gmma_columns_share_saved_layout_and_group_headers_do_not_overlap_rows(self):
        source = self.panel_source() + PANEL_SETUP + r'''
    public static string Run() {
        DrawElliotPanel panel=new DrawElliotPanel(0,"Panel-");
        ElliotPanelData live=Data("USDJPY");
        ElliotTableRowData row=live.frames[6].row;
        row.hasGmmaTrendCount=true;row.gmmaTrendCount=4;row.hasGmmaCrossCount=true;row.gmmaCrossCount=-1;
        row.isBuy=0;row.isUptrend=0;row.isAdded=1;
        live.frames[5].row.hasGmmaTrendCount=true;live.frames[5].row.gmmaTrendCount=0;
        live.frames[4].row.hasData=false;live.frames[4].row.hasGmmaCrossCount=true;live.frames[4].row.gmmaCrossCount=12;
        Check(panel.updateLive(live),"GMMA current table draws");
        Check(Text("Panel-Row5-GmmaTrend")=="+4" && Text("Panel-Row5-GmmaCross")=="-1","separate GMMA columns retain positive and negative-one counts");
        Check(Number("Panel-Row5-GmmaTrend",OBJPROP_COLOR)==clrAqua && Number("Panel-Row5-GmmaCross",OBJPROP_COLOR)==clrHotPink,"GMMA colors use their own signs despite SELL and added wave state");
        Check(Text("Panel-Row15-GmmaTrend")=="0" && Number("Panel-Row15-GmmaTrend",OBJPROP_COLOR)==clrWhite,"recorded zero is visible and neutral");
        Check(Text("Panel-Row15-GmmaCross")=="?" && Number("Panel-Row15-GmmaCross",OBJPROP_COLOR)==live.palette.unknownColor,"missing cross is unknown instead of zero");
        Check(Text("Panel-Row16385-GmmaCross")=="?","missing entire frame cannot expose stale GMMA fields");
        string trendTooltip=Objects["Panel-Row5-GmmaTrend"].texts[OBJPROP_TOOLTIP];
        string crossTooltip=Objects["Panel-Row5-GmmaCross"].texts[OBJPROP_TOOLTIP];
        Check(trendTooltip.Contains("GMMA Trend：+4") && trendTooltip.Contains("傾き"),"trend tooltip names the signed value and its slope meaning");
        Check(crossTooltip.Contains("GMMA Cross：-1") && crossTooltip.Contains("EMA30 < EMA60"),"cross tooltip explains the independently negative relationship");
        Check(Objects["Panel-Row15-GmmaCross"].texts[OBJPROP_TOOLTIP].Contains("未記録"),"missing count tooltip explains the question mark");
        Check(Text("Panel-HeaderGroupGmma")=="GMMA" && Text("Panel-HeaderGroupElliot")=="Elliot","group header titles are displayed once above their columns");
        Check(Text("Panel-HeaderGmmaTrend")=="Trend" && Text("Panel-HeaderGmmaCross")=="Cross","lower GMMA headings identify the two counts");
        long headerTop=Number("Panel-HeaderBackground",OBJPROP_YDISTANCE);
        long rowHeight=Number("Panel-Row49153-Background",OBJPROP_YSIZE);
        long headerBottom=headerTop+Number("Panel-HeaderBackground",OBJPROP_YSIZE);
        Check(Number("Panel-HeaderBackground",OBJPROP_YSIZE)==rowHeight+20,"header background includes both levels");
        Check(Number("Panel-HeaderGroupGmma",OBJPROP_YDISTANCE)==headerTop+1 && Number("Panel-HeaderGroupElliot",OBJPROP_YDISTANCE)==headerTop+1,"both group names share the top header level");
        Check(Number("Panel-HeaderTimeFrame",OBJPROP_YDISTANCE)==headerTop+13 && Number("Panel-HeaderPriceMovement",OBJPROP_YDISTANCE)==headerTop+13,"un-grouped headings are vertically centered across both levels");
        Check(Number("Panel-HeaderGmmaTrend",OBJPROP_YDISTANCE)==headerTop+23 && Number("Panel-HeaderElliotDirection",OBJPROP_YDISTANCE)==headerTop+23,"GMMA and Elliott child headings share the lower header level");
        long trendLeft=Number("Panel-HeaderGmmaTrend",OBJPROP_XDISTANCE)-3;
        long crossLeft=Number("Panel-HeaderGmmaCross",OBJPROP_XDISTANCE)-3;
        long elliotLeft=Number("Panel-HeaderElliotDirection",OBJPROP_XDISTANCE)-3;
        long tableRight=Number("Panel-HeaderBackground",OBJPROP_XDISTANCE)+Number("Panel-HeaderBackground",OBJPROP_XSIZE);
        Check(crossLeft-trendLeft==56 && elliotLeft-crossLeft==56 && tableRight-elliotLeft==536,"GMMA fits between movement and the complete Elliott region");
        Check(Number("Panel-HeaderGroupGmma",OBJPROP_XDISTANCE)==(trendLeft+elliotLeft)/2 && Number("Panel-HeaderGroupElliot",OBJPROP_XDISTANCE)==(elliotLeft+tableRight)/2,"group labels are centered over their actual child columns");
        Check(Number("Panel-HeaderGroupGmma",OBJPROP_ANCHOR)==ANCHOR_UPPER && Number("Panel-HeaderGroupElliot",OBJPROP_ANCHOR)==ANCHOR_UPPER,"center anchors keep group names centered as text widths differ");
        Check(Number("Panel-HeaderGmmaLine0",OBJPROP_YDISTANCE)==headerTop+20 && Number("Panel-HeaderGmmaLine0",OBJPROP_YSIZE)==rowHeight,"internal GMMA divider starts below its group label");
        Check(Number("Panel-HeaderGmmaLine1",OBJPROP_YDISTANCE)==headerTop && Number("Panel-HeaderGmmaLine1",OBJPROP_YSIZE)==rowHeight+20,"GMMA group boundary spans both header levels");
        Check(Number("Panel-HeaderElliotLine0",OBJPROP_YDISTANCE)==headerTop+20 && Number("Panel-HeaderGroupElliotLine",OBJPROP_YDISTANCE)==headerTop+19,"Elliott group is separated from its child headings without crossing the title");
        Check(Number("Panel-Row49153-Background",OBJPROP_YDISTANCE)==headerBottom && Number("Panel-Row49153-GmmaTrend",OBJPROP_YDISTANCE)==headerBottom+3,"first data row begins immediately below both header levels");
        Check(Number("Panel-Row1-Background",OBJPROP_YDISTANCE)==headerBottom+7*rowHeight,"eight current rows remain evenly spaced after the enlarged header");
        string[] currentNames=Objects.Keys.Where(name=>name.StartsWith("Panel-Row5-",StringComparison.Ordinal)).Select(name=>name.Replace(panel.getObjectPrefix(),"Panel-")).OrderBy(name=>name).ToArray();
        panel.onObjectClick("Panel-Row15-GmmaCross");
        Check(panel.getSelectedTimeFrame()==PERIOD_M15 && panel.isExpanded() && Text("Panel-DetailTitle")=="M15 の詳細","GMMA cell click selects and expands its timeframe through the existing row prefix");
        Check(Number("Panel-DetailTitle",OBJPROP_YDISTANCE)>=Number("Panel-Row1-Background",OBJPROP_YDISTANCE)+Number("Panel-Row1-Background",OBJPROP_YSIZE),"expanded details start after every current row");
        ElliotPanelData saved=Data("USDJPY",true);saved.frames[6].row=Clone(row);
        Check(panel.showSaved(saved),"GMMA saved table draws");
        string[] savedNames=Objects.Keys.Where(name=>name.StartsWith("Panel-Row5-",StringComparison.Ordinal)).Select(name=>name.Replace(panel.getObjectPrefix(),"Panel-")).OrderBy(name=>name).ToArray();
        Check(currentNames.SequenceEqual(savedNames),"current and saved rows have identical objects including both GMMA columns");
        Check(Text("Panel-Row5-GmmaTrend")=="+4" && Text("Panel-Row5-GmmaCross")=="-1" && Number("Panel-Row5-GmmaCross",OBJPROP_COLOR)==clrHotPink,"saved counts use the same value and sign color rules");
        Check(Objects["Panel-Row5-GmmaTrend"].texts[OBJPROP_TOOLTIP]==trendTooltip && Objects["Panel-Row5-GmmaCross"].texts[OBJPROP_TOOLTIP]==crossTooltip,"current and saved GMMA cells have identical explanatory tooltips");
        Check(Number("Panel-DetailTitle",OBJPROP_YDISTANCE)>=Number("Panel-Row5-Background",OBJPROP_YDISTANCE)+Number("Panel-Row5-Background",OBJPROP_YSIZE),"saved details also start after the last of seven rows");
        panel.setExpanded(false);panel.onObjectClick("Panel-Row5-GmmaTrend");
        Check(panel.isExpanded() && panel.getSelectedTimeFrame()==PERIOD_M5,"trend cell retains saved row selection");
        Width=983;Check(panel.draw(),"narrow saved table redraws");
        Check(Text("Panel-Row5-GmmaTrend")=="+4" && Text("Panel-Row5-GmmaCross")=="-1" && Objects.ContainsKey("Panel-Row5-Elliot"),"narrow fallback retains both GMMA values alongside the composite Elliott cell");
        Check(Objects.ContainsKey("Panel-HeaderGroupGmma") && !Objects.ContainsKey("Panel-HeaderGroupElliot") && !Objects.ContainsKey("Panel-HeaderElliotDirection"),"narrow fallback removes split Elliott group objects while retaining GMMA headings");
        Check(Number("Panel-HeaderBackground",OBJPROP_XDISTANCE)+Number("Panel-HeaderBackground",OBJPROP_XSIZE)<=Number("Panel-Background",OBJPROP_XDISTANCE)+Number("Panel-Background",OBJPROP_XSIZE),"narrow table ends within the shared frame");
        Check(panel.getSelectedTimeFrame()==PERIOD_M5 && panel.isSavedMode(),"header fallback preserves selection and data source");
        return "PASS "+checks+" GMMA grouped header assertions";
    }
}
'''
        self.assertRegex(run_panel_csharp(source, "[PanelFixture]::Run()\n"), r"PASS \d+ GMMA grouped header assertions")

    def test_split_elliot_cells_keep_values_tooltips_selection_and_narrow_fallback(self):
        source = self.panel_source() + PANEL_SETUP + r'''
    public static string Run() {
        DrawElliotPanel panel=new DrawElliotPanel(0,"Panel-");
        ElliotPanelData live=Data("USDJPY");
        ElliotTableRowData row=live.frames[6].row;
        row.mainWave="3";row.subWave="iii";row.originalWave="5";row.isConfirmed=0;row.isAdded=1;
        row.previousMotiveSubElliotIndex=3;row.originalWaveIndex=5;
        row.hasPointFibonacciExpansionPercent=true;row.pointFibonacciExpansionPercent=161.8;
        row.pointPipsDiff=-12.5;row.pointRate=159.234;
        Check(panel.updateLive(live),"wide live panel draws split wave cells");
        string[] keys={"Direction","MainWave","SubWave","OriginalWave","Confirmed","Added","PreviousSub","Fibonacci","Pips","Price"};
        string[] values={"▼","3","iii","5","未確定","★","3","FE 161.8%","-12.5p","159.234"};
        string[] headers={"方向","主波","副波","元波","確定","補完","前副","F／FE","値幅","価格"};
        for(int i=0;i<keys.Length;i++) {
            string name="Panel-Row5-Elliot"+keys[i];
            Check(Text(name)==values[i],"independent wave cell value: "+keys[i]);
            Check(Text("Panel-HeaderElliot"+keys[i])==headers[i],"independent wave header: "+keys[i]);
            Check(Number(name,OBJPROP_FONTSIZE)==11,"split cells preserve configured font size: "+keys[i]);
            Check(Objects[name].texts[OBJPROP_TOOLTIP].Contains(values[i]),"cell tooltip preserves complete value: "+keys[i]);
        }
        Check(!Objects.ContainsKey("Panel-Row5-Elliot") && Text("Panel-Row5-BuySell")=="BUY","split wave direction stays separate from unchanged analysis column");
        string[] liveNames=Objects.Keys.Where(name=>name.StartsWith("Panel-Row5-Elliot",StringComparison.Ordinal)).Select(name=>name.Replace(panel.getObjectPrefix(),"Panel-")).OrderBy(name=>name).ToArray();
        ElliotPanelData saved=Data("USDJPY",true);saved.frames[6].row=Clone(row);
        panel.showSaved(saved);
        string[] savedNames=Objects.Keys.Where(name=>name.StartsWith("Panel-Row5-Elliot",StringComparison.Ordinal)).Select(name=>name.Replace(panel.getObjectPrefix(),"Panel-")).OrderBy(name=>name).ToArray();
        Check(liveNames.SequenceEqual(savedNames),"live and saved use identical split object names and separators");
        for(int i=0;i<keys.Length;i++) Check(Text("Panel-Row5-Elliot"+keys[i])==values[i],"saved adapter data uses same visible cells: "+keys[i]);
        panel.setExpanded(false);
        Check(panel.onObjectClick("Panel-Row15-ElliotPrice")==DrawElliotPanel.ELLIOT_PANEL_ACTION_HANDLED && panel.getSelectedTimeFrame()==PERIOD_M15 && panel.isExpanded(),"split price cell retains row selection and detail expansion");
        Check(Text("Panel-DetailTitle")=="M15 の詳細","split selection shows the correct detail timeframe");
        panel.setExpanded(false);panel.onObjectClick("Panel-Row5-ElliotSubWave");
        Check(panel.getSelectedTimeFrame()==PERIOD_M5,"any split cell selects the corresponding timeframe");
        Width=983;panel.draw();
        Check(Objects.ContainsKey("Panel-Row5-Elliot") && !Objects.ContainsKey("Panel-Row5-ElliotDirection"),"panel width below 960 restores one wave column and removes split cells");
        Check(Objects["Panel-Row5-Elliot"].texts[OBJPROP_TOOLTIP].Contains("▼3.iii[5][FE161.8%]<-12.5p>159.234"),"narrow fallback keeps the full established wave summary in its tooltip");
        Check(Text("Panel-HeaderElliot")=="Elliot" && panel.getSelectedTimeFrame()==PERIOD_M5,"narrow fallback preserves selected timeframe and original header");
        Width=984;panel.draw();
        Check(!Objects.ContainsKey("Panel-Row5-Elliot") && Objects.ContainsKey("Panel-Row5-ElliotDirection"),"960-pixel panel threshold restores split columns");
        Check(panel.getSelectedTimeFrame()==PERIOD_M5 && panel.isSavedMode(),"resize never changes selected data source");
        return "PASS "+checks+" split panel assertions";
    }
}
'''
        self.assertRegex(run_panel_csharp(source, "[PanelFixture]::Run()\n"), r"PASS \d+ split panel assertions")

    def test_split_elliot_renderer_fits_the_full_536_pixel_region_and_retains_long_tooltips(self):
        source = self.panel_source() + PANEL_SETUP + r'''
    public static string Run() {
        ElliotTableRowData row=new ElliotTableRowData { hasData=true,mainWave="3",subWave=new string('i',24),
            originalWave="5",isUptrend=0,isBuy=1,isConfirmed=0,isAdded=1,previousMotiveSubElliotIndex=3,
            originalWaveIndex=5,hasPointFibonacciExpansionPercent=true,pointFibonacciExpansionPercent=161.8,
            hasPointPipsDiff=true,pointPipsDiff=-12.5,hasPointRate=true,pointRate=159.234 };
        ElliotTablePalette palette=new ElliotTablePalette();ElliotTableLayout layout=new ElliotTableLayout();
        layout.originX=40;layout.originY=70;layout.columnXs[4]=400;layout.columnWidths[4]=536;
        layout.paddingX=3;layout.paddingY=3;layout.clipText=true;layout.showSeparators=true;layout.splitElliot=true;
        layout.showGmma=true;layout.gmmaColumnXs[0]=288;layout.gmmaColumnXs[1]=344;
        layout.gmmaColumnWidths[0]=56;layout.gmmaColumnWidths[1]=56;
        for(int i=0;i<4;i++) layout.columnVisible[i]=false;
        Check(DrawElliotTable.drawHeader(0,"Header-",layout) && DrawElliotTable.drawRow(0,"Row-",row,3,palette,layout),"536-pixel split area draws header and row");
        string[] keys={"Direction","MainWave","SubWave","OriginalWave","Confirmed","Added","PreviousSub","Fibonacci","Pips","Price"};
        int[] widths={40,40,44,40,56,40,40,94,68,74};
        long start=Number("Row-ElliotDirection",OBJPROP_XDISTANCE),position=start;
        for(int i=0;i<keys.Length;i++) {
            string name="Row-Elliot"+keys[i];
            Check(Number(name,OBJPROP_XDISTANCE)==position,"successive cell position matches allocated width: "+keys[i]);
            Check(Number("Header-Elliot"+keys[i],OBJPROP_XDISTANCE)==position,"header aligns with its data cell: "+keys[i]);
            Check(Text(name).Length*8<=widths[i],"measured text stays inside subcolumn: "+keys[i]);
            Check(Number(name,OBJPROP_YDISTANCE)==73 && Number(name,OBJPROP_FONTSIZE)==11,"split labels retain row position and font");
            position+=widths[i];
        }
        Check(position-start==536 && Number("Row-ElliotPrice",OBJPROP_XDISTANCE)+Text("Row-ElliotPrice").Length*8<=40+400+536,"final price text stays inside the complete 536-pixel region");
        Check(Text("Row-ElliotSubWave").EndsWith("…") && Objects["Row-ElliotSubWave"].texts[OBJPROP_TOOLTIP].Contains(row.subWave),"long subwave is clipped but complete value remains in tooltip");
        Check(!Objects.ContainsKey("Row-Elliot") && !Objects.ContainsKey("Header-Elliot"),"split rendering creates no overlapping composite wave label");
        ElliotTableLayout legacy=new ElliotTableLayout();legacy.columnXs[4]=400;legacy.columnWidths[4]=536;
        for(int i=0;i<4;i++) legacy.columnVisible[i]=false;
        Check(!legacy.splitElliot && !legacy.showGmma && legacy.groupHeaderHeight==0 && DrawElliotTable.drawRow(0,"Legacy-",row,3,palette,legacy),"nonpanel callers keep original default layout");
        Check(Text("Legacy-Elliot").Contains("▼3."+row.subWave) && !Objects.ContainsKey("Legacy-ElliotMainWave"),"legacy chart table retains its composite wave text");
        Check(!Objects.ContainsKey("Legacy-GmmaTrend") && !Objects.ContainsKey("Legacy-GmmaCross"),"legacy five-column drawing does not add duplicate GMMA labels");
        layout.columnWidths[4]=0;
        Check(DrawElliotTable.drawRow(0,"Row-",row,3,palette,layout) && !Objects.ContainsKey("Row-ElliotPrice"),"empty fitted label removes its prior object instead of retaining a stale value or MT5 Label");
        layout.columnWidths[4]=536;
        FailName="Failed-ElliotSubWave";
        Check(!DrawElliotTable.drawRow(0,"Failed-",row,3,palette,layout) && Objects.ContainsKey("Failed-ElliotPrice"),"split-cell creation failure is reported while later cells still draw");
        return "PASS "+checks+" split renderer assertions";
    }
}
'''
        self.assertRegex(run_panel_csharp(source, "[PanelFixture]::Run()\n"), r"PASS \d+ split renderer assertions")

    def test_split_elliot_formatter_distinguishes_unknown_absent_and_recorded_zero(self):
        source = "using System;using System.Globalization;\n" + table_fixture() + r'''
public class SplitFormatterFixture {
    static int checks;
    static void Check(bool value,string message) { checks++;if(!value) throw new Exception(message); }
    public static string Run() {
        ElliotTableRowData row=new ElliotTableRowData();
        for(int i=0;i<10;i++) Check(ElliotTableFormatter.elliotCellText(row,i,3)=="?","missing entire row remains unknown: "+i);
        row.hasData=true;row.mainWave=null;row.subWave=null;row.originalWave=null;
        Check(ElliotTableFormatter.elliotCellText(row,1,3)=="?" && ElliotTableFormatter.elliotCellText(row,2,3)=="—" && ElliotTableFormatter.elliotCellText(row,3,3)=="?","unknown main/original wave differs from absent optional subwave");
        row.isUptrend=0;row.isConfirmed=0;row.isAdded=0;row.previousMotiveSubElliotIndex=0;row.originalWaveIndex=1;
        Check(ElliotTableFormatter.elliotCellText(row,0,3)=="▼" && ElliotTableFormatter.elliotCellText(row,4,3)=="未確定","false flags have meaningful display values");
        Check(ElliotTableFormatter.elliotCellText(row,5,3)=="—" && ElliotTableFormatter.elliotCellText(row,6,3)=="—" && ElliotTableFormatter.elliotCellText(row,7,3)=="—","normal point, no preceding subwave and wave one use absence marker");
        row.originalWaveIndex=2;row.pointFibonacciPercent=0;row.hasPointFibonacciPercent=true;
        row.hasPointFibonacciExpansionPercent=true;row.pointFibonacciExpansionPercent=161.8;
        Check(ElliotTableFormatter.elliotCellText(row,7,3)=="F 0.0%","even original wave selects recorded zero retracement");
        row.originalWaveIndex=3;
        Check(ElliotTableFormatter.elliotCellText(row,7,3)=="FE 161.8%","odd original wave selects expansion independently of current label");
        row.hasPointFibonacciExpansionPercent=false;
        Check(ElliotTableFormatter.elliotCellText(row,7,3)=="FE ?","missing expansion is explicit without inventing zero");
        row.originalWaveIndex=2;row.hasPointFibonacciPercent=false;
        Check(ElliotTableFormatter.elliotCellText(row,7,3)=="F ?","missing retracement retains known F type");
        row.originalWaveIndex=-1;
        Check(ElliotTableFormatter.elliotCellText(row,7,3)=="?","unknown original wave does not infer F or FE");
        row.hasPointPipsDiff=true;row.pointPipsDiff=0;row.hasPointRate=true;row.pointRate=0;
        Check(ElliotTableFormatter.elliotCellText(row,8,3)=="0.0p" && ElliotTableFormatter.elliotCellText(row,9,3)=="0.000","recorded zeros remain numeric in split cells");
        row.hasPointPipsDiff=false;row.hasPointRate=false;
        Check(ElliotTableFormatter.elliotCellText(row,8,3)=="?" && ElliotTableFormatter.elliotCellText(row,9,3)=="?","missing numeric metrics differ from zero");
        Check(ElliotTableFormatter.elliotCellTooltip(row,8,3).Contains("?") && ElliotTableFormatter.elliotCellTooltip(row,8,3).Contains("未記録"),"unknown marker tooltip explains missing value");
        Check(ElliotTableFormatter.elliotCellTooltip(row,5,3).Contains("該当なし"),"absence tooltip explains normal point");
        row.isAdded=1;
        Check(ElliotTableFormatter.elliotCellText(row,5,3)=="★" && ElliotTableFormatter.elliotCellTooltip(row,5,3).Contains("補完"),"added marker has an explanatory tooltip");
        row.mainWave="3";row.subWave=new string('i',40);
        Check(ElliotTableFormatter.elliotCellTooltip(row,2,3).Contains(row.subWave),"formatter preserves full subwave for renderer tooltip");
        row.pointRate=1.234567891;row.hasPointRate=true;
        Check(ElliotTableFormatter.elliotCellText(row,9,11)=="1.23456789","price precision retains existing eight-digit limit");
        ElliotTablePalette palette=new ElliotTablePalette();
        row.hasGmmaTrendCount=true;row.gmmaTrendCount=int.MinValue;
        row.hasGmmaCrossCount=true;row.gmmaCrossCount=int.MaxValue;
        Check(ElliotTableFormatter.gmmaCellText(row,0)=="-2147483648" && ElliotTableFormatter.gmmaCellText(row,1)=="+2147483647","GMMA formatter preserves the full signed integer range");
        Check(ElliotTableFormatter.gmmaCellColor(row,0,palette)==palette.downColor && ElliotTableFormatter.gmmaCellColor(row,1,palette)==palette.upColor,"GMMA extreme counts retain sign colors without overflow");
        Check(ElliotTableFormatter.gmmaCellTooltip(row,1).Contains("+2147483647"),"GMMA tooltip preserves the full unclipped signed value");
        Check(ElliotTableFormatter.gmmaCellText(row,-1)=="" && ElliotTableFormatter.gmmaCellTooltip(row,2)=="","invalid GMMA columns are not displayed");
        row.clear();
        Check(!row.hasGmmaTrendCount && !row.hasGmmaCrossCount && row.gmmaTrendCount==0 && row.gmmaCrossCount==0,"row reset clears both previous GMMA values and availability flags");
        Check(ElliotTableFormatter.gmmaCellText(row,0)=="?" && ElliotTableFormatter.gmmaCellColor(row,1,palette)==palette.unknownColor,"reset count defaults cannot be mistaken for recorded zero");
        return "PASS "+checks+" split formatter assertions";
    }
}
'''
        self.assertRegex(run_csharp(source, "[SplitFormatterFixture]::Run()\n"), r"PASS \d+ split formatter assertions")

    def test_saved_selection_survives_live_updates_and_returns_to_latest_cache(self):
        source = self.panel_source() + PANEL_SETUP + r'''
    public static string Run() {
        DrawElliotPanel panel=new DrawElliotPanel(0,"Panel-");
        Check(panel.isVisible() && !panel.isExpanded() && !panel.isSavedMode(),"initial mode is visible current list");
        ElliotPanelData live=Data("LIVE-A"),saved=Data("SAVED-A",true);
        Check(panel.updateLive(live) && Text("Panel-Title").Contains("現在"),"live data uses current header");
        Check(Objects.ContainsKey("Panel-Row1-TimeFrame") && !Objects.ContainsKey("Panel-DetailTitle"),"live M1 appears in compact list");
        Check(!Objects.ContainsKey("Panel-Previous") && !Objects.ContainsKey("Panel-Live"),"current mode does not show history navigation");
        Check(!Objects.ContainsKey("Panel-Metadata"),"empty text does not create MT5's default Label object");
        panel.onObjectClick("Panel-Row1-ElliotMainWave");
        Check(panel.getSelectedTimeFrame()==PERIOD_M1,"row click stores timeframe rather than array index");
        Check(panel.showSaved(saved) && panel.isSavedMode() && panel.isExpanded(),"marker selection opens saved details");
        Check(panel.getSelectedTimeFrame()==PERIOD_M5 && !Objects.ContainsKey("Panel-Row1-TimeFrame"),"saved source without M1 falls back to M5 without inventing a row");
        Check(Text("Panel-Title").Contains("保存") && Text("Panel-DetailTitle")=="M5 の詳細","same panel switches title, rows and selected details");
        Check(Objects.ContainsKey("Panel-Previous") && Objects.ContainsKey("Panel-Next") && Objects.ContainsKey("Panel-Live"),"saved navigation and current button appear together");
        Check(Text("Panel-StrengthTitle").Contains("履歴") && Number("Panel-StrengthLongMedium3",OBJPROP_COLOR)==clrAqua && Number("Panel-StrengthLongMedium4",OBJPROP_COLOR)==clrHotPink,"saved strength source and independent gap/delta colors retained");
        panel.onObjectClick("Panel-Row15-ElliotMainWave");
        int objectCount=Objects.Count;
        live.symbolName="LIVE-B";live.frames[7].row.mainWave="5";
        panel.updateLive(live);
        Check(Objects.Count==objectCount && Text("Panel-Title").Contains("SAVED-A") && panel.getSelectedTimeFrame()==PERIOD_M15,"live refresh does not redraw saved content or reset selected timeframe");
        live.symbolName="CALLER-MUTATED";
        Check(panel.onObjectClick("Panel-Previous")==DrawElliotPanel.ELLIOT_PANEL_ACTION_PREVIOUS && panel.onObjectClick("Panel-Next")==DrawElliotPanel.ELLIOT_PANEL_ACTION_NEXT,"navigation returns actions for the cached history controller");
        long selectedTime=panel.getSavedTime();
        panel.onObjectClick("Panel-Expand");
        Check(!panel.isExpanded() && !Objects.ContainsKey("Panel-DetailTitle"),"collapse removes details using the same frame");
        saved.savedTime+=300;saved.symbolName="SAVED-B";saved.canNext=false;
        panel.showSaved(saved);
        Check(!panel.isExpanded() && panel.getSelectedTimeFrame()==PERIOD_M15 && panel.getSavedTime()==selectedTime+300,"previous/next replacement preserves collapse and timeframe");
        Check(panel.onObjectClick("Panel-Next")==DrawElliotPanel.ELLIOT_PANEL_ACTION_HANDLED && Number("Panel-Next",OBJPROP_STATE)==0,"disabled edge consumes click without navigating");
        Check(panel.onObjectClick("Other-Live")==DrawElliotPanel.ELLIOT_PANEL_ACTION_NONE && panel.isSavedMode(),"other panel controls cannot change this view");
        Check(panel.onObjectClick("Panel-Live")==DrawElliotPanel.ELLIOT_PANEL_ACTION_HANDLED && !panel.isSavedMode(),"current button restores current mode");
        Check(Text("Panel-Title").Contains("LIVE-B") && !Text("Panel-Title").Contains("CALLER-MUTATED"),"return displays latest copied live cache");
        Check(panel.getSelectedTimeFrame()==PERIOD_M15 && panel.getSavedTime()==0 && !Objects.ContainsKey("Panel-Next"),"return preserves timeframe and clears saved navigation display");
        Check(Text("Panel-Row1-ElliotDirection")=="▼" && Text("Panel-Row1-ElliotMainWave")=="5","live values updated while history was selected");
        panel.showSaved(saved);
        Check(panel.onObjectClick("Panel-Close")==DrawElliotPanel.ELLIOT_PANEL_ACTION_CLOSED && !panel.isVisible(),"close hides one shared panel");
        Check(Objects.Count==0 && !panel.containsPoint(20,20),"closed panel removes its objects and no longer intercepts hover");
        panel.updateLive(Data("LIVE-C"));saved.canNext=true;panel.updateSaved(saved);
        Check(Objects.Count==0 && !panel.isVisible() && panel.isSavedMode(),"background cache updates cannot reopen a closed panel");
        panel.setVisible(true);
        Check(panel.isSavedMode() && Text("Panel-Title").Contains("SAVED-B"),"reopen preserves selected mode");
        panel.showLive();
        Check(Text("Panel-Title").Contains("LIVE-C"),"current button after close uses the newest cache");
        panel.onObjectClick("Panel-Row1-ElliotMainWave");
        ElliotPanelData shorter=Data("H1");shorter.rowCount=5;
        panel.updateLive(shorter);
        Check(panel.getSelectedTimeFrame()==PERIOD_H1,"missing selected timeframe and M5 fall back to final available row");
        return "PASS "+checks+" shared panel state assertions";
    }
}
'''
        self.assertRegex(run_panel_csharp(source, "[PanelFixture]::Run()\n"), r"PASS \d+ shared panel state assertions")

    def test_panel_layout_details_missing_values_and_narrow_chart_controls(self):
        source = self.panel_source() + PANEL_SETUP + r'''
    public static string Run() {
        DrawElliotPanel panel=new DrawElliotPanel(0,"Panel-");
        ElliotPanelData live=Data("USDJPY");
        live.frames[6].row.pointRate=0;live.frames[6].row.hasPointRate=true;
        live.frames[6].row.subWave=null;live.frames[6].row.originalWave=null;
        panel.updateLive(live);panel.setExpanded(true);
        Check(Text("Panel-DetailValue1")=="なし" && Text("Panel-DetailValue2")=="未記録","absent subwave and unknown original wave retain different meanings");
        Check(Text("Panel-DetailValue8")=="0.0 pips" && Text("Panel-DetailValue9")=="0.000","recorded zero in details never becomes missing");
        Check(Text("Panel-DetailValue10").StartsWith("JST ") && Text("Panel-DetailValue11")=="下降 ▼","point time and wave direction remain independent of BUY analysis");
        Check(Objects.ContainsKey("Panel-ExtraTitle") && Text("Panel-ExtraValue0")=="+2","expanded current panel includes extra oscillators");
        long panelBottom=Number("Panel-Background",OBJPROP_YDISTANCE)+Number("Panel-Background",OBJPROP_YSIZE);
        Check(Number("Panel-Hint",OBJPROP_YDISTANCE)<panelBottom && Number("Panel-ExtraValue0",OBJPROP_YDISTANCE)<Number("Panel-Hint",OBJPROP_YDISTANCE),"details, strength, extras and hint occupy separate rows");
        Check(panel.containsPoint(20,20) && !panel.containsPoint(0,0) && !panel.containsPoint(1300,790),"hover interception matches panel bounds");
        ElliotPanelData saved=Data("USDJPY",true);
        saved.frames[6].row.hasData=false;panel.showSaved(saved);
        Check(Text("Panel-DetailValue9")=="未記録" && Text("Panel-DetailValue10")=="未記録","missing saved row does not inherit live values");
        Check(!Objects.ContainsKey("Panel-ExtraTitle"),"saved data without extra indicators removes live extra objects");
        ObjectCreate(0,"Other-Label",OBJ_LABEL,0,0,0);panel.draw();
        Check(Objects.ContainsKey("Other-Label"),"redraw only removes owned prefix");
        Width=700;Height=430;panel.draw();
        Check(Objects.ContainsKey("Panel-Row5-TimeFrame") && !Objects.ContainsKey("Panel-DetailTitle") && Text("Panel-Hint").Contains("広げる"),"short chart retains list and explains hidden details");
        Check(Number("Panel-Row5-Background",OBJPROP_YSIZE)==20 && Number("Panel-HeaderBackground",OBJPROP_YSIZE)==40,"compressed rows preserve the extra group heading height");
        Check(Number("Panel-Row49153-Background",OBJPROP_YDISTANCE)==Number("Panel-HeaderBackground",OBJPROP_YDISTANCE)+Number("Panel-HeaderBackground",OBJPROP_YSIZE),"compressed first row still starts below the complete two-level header");
        Check(Number("Panel-Background",OBJPROP_XDISTANCE)+Number("Panel-Background",OBJPROP_XSIZE)<=Width && Number("Panel-Background",OBJPROP_YDISTANCE)+Number("Panel-Background",OBJPROP_YSIZE)<=Height,"panel frame fits chart bounds");
        Width=400;Height=220;panel.draw();
        Check(Objects.ContainsKey("Panel-Small") && !Objects.ContainsKey("Panel-Row5-TimeFrame"),"narrow chart shows explicit list size message");
        Check(Objects.ContainsKey("Panel-Live") && Objects.ContainsKey("Panel-Close") && Objects.ContainsKey("Panel-Expand"),"narrow chart keeps return, close and fold controls available");
        foreach(string key in new string[]{"Live","Close","Expand","Previous","Next"}) {
            Check(Number("Panel-"+key,OBJPROP_XDISTANCE)>=0 && Number("Panel-"+key,OBJPROP_XDISTANCE)+Number("Panel-"+key,OBJPROP_XSIZE)<=Width,"narrow button inside chart: "+key);
        }
        Width=1400;Height=800;panel.draw();FailName="Panel-Title";
        ObjectDelete(0,"Panel-Title");
        Check(!panel.draw() && Objects.ContainsKey("Panel-Close"),"drawing failure reported without suppressing remaining controls");
        FailName="";saved.rowCount=0;saved.status="このM5時刻の記録はありません。";
        panel.showSaved(saved);
        Check(Text("Panel-Empty").Contains("記録はありません") && Objects.ContainsKey("Panel-Live") && !Objects.ContainsKey("Panel-Row5-TimeFrame"),"missing observation keeps navigation and explanation without invented rows");
        return "PASS "+checks+" shared panel layout assertions";
    }
}
'''
        self.assertRegex(run_panel_csharp(source, "[PanelFixture]::Run()\n"), r"PASS \d+ shared panel layout assertions")


LIVE_API = r'''
public class MarketContext {
    public string symbolName="USDJPY",timeFrameLabel="M1";public int timeFrame=1,digits=3;
}
public class TradeTimeInfo { public long jstTime=1795525200,serverTime=1795500000; }
public class TimeJapanUtil { public static long getJapanTime(long time) { return time+7*3600; } }
public class StringUtil { public static string addSign(int value) { return value.ToString("+0;-0;0",CultureInfo.InvariantCulture); } }
public class PriceMovementInfo {
    public bool isValid=true,isSpreadValid=true;public int level=3;public double activityRatio=1.25;
    public double averageRangePips=2.5,referenceAtrPips=2,rangeSpreadRatio=5;public long referenceBarTime=1795499700;
}
public class Ema { public bool isBuy=true,isSell=false; }
public class Stochastic { public int count; }
public class Oscillator {
    public Ema ema200=new Ema();public PriceMovementInfo priceMovement=new PriceMovementInfo();
    public Stochastic stochasticShort=new Stochastic { count=2 },stochasticMiddle=new Stochastic { count=-3 },stochasticLong=new Stochastic();
    public int gmmaTrendCount=4,gmmaCrossCount=-5;
    public string getStochasticMainOrderText() { return "SMO fixture"; }
    public int getStochasticMainOrderColor() { return 42; }
}
public class ZigZagPoint {
    public string elliotLabel="3",subElliotLabel="i",orgElliotLabel="2";
    public int orgElliotIndex=2;public bool isAddedPoint;
    public long barTime=1795499700;
    public double pipsDiff=-12.5,fibonacciPercent=61.8,fibonacciExpansionPercent=161.8,rate=159.234;
}
public class Wave {
    public bool isUptrend=false,isConfirmed=true;public int previous=3;
    public string previousLastElliotLabel="A";public ZigZagPoint point=new ZigZagPoint();
    public ZigZagPoint getLatestPoint() { return point; }
    public int getPreviousMotiveSubElliotIndex() { return previous; }
}
public class Elliot {
    public bool isBuy=true;public MarketContext marketContext=new MarketContext();
    public Oscillator oscillator=new Oscillator();public Wave wave=new Wave();
    public Wave getLatestWave() { return wave; }
}
public class ElliotList {
    public Elliot[] values=new Elliot[0];public int Total() { return values.Length; }
    public Elliot At(int index) { return values[index]; }
}
public class ElliotAll {
    public MarketContext marketContext=new MarketContext();public TradeTimeInfo tradeTimeInfo=new TradeTimeInfo();
    public ElliotList elliotList=new ElliotList();public string symbolNameLeft="USD",symbolNameRight="JPY";
}
public class CurrencyStrengthPairRankInfo {
    public string baseCurrency="USD",quoteCurrency="JPY";
    public long m5BarTime=1795500000,runId=19;
    public int baseLongMediumTermAverageRank=2,quoteLongMediumTermAverageRank=7,
        baseMediumShortTermAverageRank=6,quoteMediumShortTermAverageRank=3;
}
public class CurrencyStrengthRankGapDirectionInfo {
    public bool enabled,waiting,currentAvailable,hasPrevious;
    public long targetM5BarTime;public int currentGap,previousGap;
}
public class CurrencyStrengthExecutionInfo : MqlApi {
    public const int CURRENCY_STRENGTH_EXECUTION_STATUS_ERROR=-1,CURRENCY_STRENGTH_EXECUTION_STATUS_NOT_QUERIED=0,
        CURRENCY_STRENGTH_EXECUTION_STATUS_DATABASE_NOT_FOUND=1,CURRENCY_STRENGTH_EXECUTION_STATUS_RECORD_NOT_FOUND=2,
        CURRENCY_STRENGTH_EXECUTION_STATUS_FOUND=3;
    public int status=3;public long targetM5BarTime=1795500000;public string sourceMode="LIVE";
    public CurrencyStrengthPairRankInfo pairRankInfo=new CurrencyStrengthPairRankInfo();
    public CurrencyStrengthRankGapDirectionInfo longMediumGapDirection=new CurrencyStrengthRankGapDirectionInfo(),
        mediumShortGapDirection=new CurrencyStrengthRankGapDirectionInfo();
'''


def live_fixture():
    execution = (ROOT / "Include/Mstng/Strength/CurrencyStrengthExecutionInfo.mqh").read_text(encoding="utf-8-sig")
    execution = execution.replace(") const {", ") {")
    result = LIVE_API + extracted_methods(execution, ("hasValidRanks", "isAvailable", "isExactM5Bar")) + "}\n"
    source = (DRAW / "ElliotPanelLiveAdapter.mqh").read_text(encoding="utf-8-sig")
    opening = source.index("class ElliotPanelLiveAdapter {") + len("class ElliotPanelLiveAdapter {")
    body = source[opening:block_end(code_only(source), opening - 1)]
    body = re.sub(r"\b(?:public|private)\s*:", "", body)
    body = syntax(body)
    body = re.sub(r"\b(ElliotAll|Elliot|Wave|ZigZagPoint)\s*\*", r"\1 ", body)
    body = re.sub(r"\(int\)((?:fromElliot|fromWave|point|fromPriceMovement)\.[\w.]+)",
                  r"Convert.ToInt32(\1)", body)
    body = re.sub(r"^(\s{4})(?=static\s+)", r"\1public ", body, flags=re.M)
    result += "public class ElliotPanelLiveAdapter : CurrencyStrengthExecutionInfo {\n" + body + "}\n"
    return result


class ElliotPanelLiveTests(unittest.TestCase):
    def test_live_panel_keeps_analysis_times_rows_extra_indicators_and_strength_sources(self):
        source = "using System;using System.Globalization;using System.Collections.Generic;using System.Linq;\n"
        source += API + table_fixture() + panel_data_fixture() + live_fixture() + r'''
public class LivePanelFixture : MqlApi {
    static int checks;
    static void Check(bool value,string message) { checks++;if(!value) throw new Exception(message); }
    public static string Run() {
        ElliotPanelData data=new ElliotPanelData();CurrencyStrengthExecutionInfo strength=new CurrencyStrengthExecutionInfo();
        Check(!ElliotPanelLiveAdapter.build(null,strength,true,"加重",data) && data.rowCount==0 && data.status.Contains("準備待ち"),"missing analysis has an explicit state");
        ElliotAll all=new ElliotAll();Elliot first=new Elliot(),second=new Elliot();
        second.marketContext.timeFrame=5;second.marketContext.timeFrameLabel="M5";
        all.elliotList.values=new Elliot[]{first,null,second};
        Check(ElliotPanelLiveAdapter.build(all,strength,true,"加重",data),"available analysis builds one neutral panel");
        Check(data.rowCount==2 && data.frames[0].timeFrame==5 && data.frames[1].timeFrame==1,"analysis order reversed, null entries skipped, live M1 preserved");
        Check(data.symbolName=="USDJPY" && data.digits==3 && data.headerTime.StartsWith("分析 JST ") && data.metadata.Contains("チャート M1"),"symbol, precision and analysis timestamp retained");
        Check(data.frames[1].pointTime==first.wave.point.barTime && data.frames[1].pointJstTime==first.wave.point.barTime+7*3600,"point timestamp is separate from analysis timestamp");
        Check(data.frames[1].movementTooltip.Contains("2.5 pips") && data.frames[1].movementTooltip.Contains("ATR14") && data.frames[1].movementTooltip.Contains("5.00倍"),"live movement details remain available through panel cells");
        Check(data.frames[1].extraCount==5 && data.frames[1].extraValues[0]=="SMO fixture" && data.frames[1].extraColors[0]==42,"non-GMMA extra indicators remain in detail view");
        Check(data.frames[1].extraValues[1]=="+2" && data.frames[1].extraValues[2]=="-3" && data.frames[1].extraValues[3]=="0","oscillator counts preserve sign and recorded zero");
        Check(data.frames[1].extraColors[1]==data.palette.upColor && data.frames[1].extraColors[2]==data.palette.downColor && data.frames[1].extraColors[3]==data.palette.neutralColor,"extra indicator colors share the table palette");
        Check(data.frames[1].extraValues[4]=="A" && data.frames[1].extraColors[4]==data.palette.neutralColor,"previous corrective wave preserves its neutral color");
        Check(data.frames[1].row.hasGmmaTrendCount && data.frames[1].row.gmmaTrendCount==4 && data.frames[1].row.hasGmmaCrossCount && data.frames[1].row.gmmaCrossCount==-5,"GMMA counts move to the common table data");
        Check(!data.frames[1].extraLabels.Take(data.frames[1].extraCount).Any(label=>label.Contains("GMMA")),"GMMA is not duplicated in expanded extra indicators");
        Check(data.strength.status=="" && data.strength.longMedium.gap==5 && data.strength.mediumShort.gap==-3,"current rank direction is retained independently by period");
        Check(!data.strength.longMedium.comparable && !data.strength.mediumShort.comparable,"no previous cache is never invented as zero delta");
        Check(data.strength.title.Contains("現在") && data.strength.title.Contains("LIVE") && data.strength.tooltip.Contains("Run 19"),"current source is explicit");
        CurrencyStrengthRankGapDirectionInfo direction=strength.longMediumGapDirection;
        direction.enabled=true;direction.currentAvailable=true;direction.hasPrevious=true;direction.targetM5BarTime=strength.targetM5BarTime;direction.currentGap=5;direction.previousGap=7;
        ElliotPanelLiveAdapter.build(all,strength,true,"加重",data);
        Check(data.strength.longMedium.comparable && data.strength.longMedium.delta==-2,"positive rank gap can shrink");
        direction.waiting=true;ElliotPanelLiveAdapter.build(all,strength,true,"加重",data);
        Check(!data.strength.longMedium.comparable && data.strength.longMedium.delta==0,"waiting invalidates the previous comparison");
        direction.waiting=false;direction.currentGap=4;ElliotPanelLiveAdapter.build(all,strength,true,"加重",data);
        Check(!data.strength.longMedium.comparable,"different current rank cache cannot be compared");
        direction.currentGap=5;direction.targetM5BarTime-=300;ElliotPanelLiveAdapter.build(all,strength,true,"加重",data);
        Check(!data.strength.longMedium.comparable,"different M5 comparison cache rejected");
        strength.pairRankInfo.m5BarTime-=300;ElliotPanelLiveAdapter.build(all,strength,true,"加重",data);
        Check(data.strength.status.Contains("不一致") && !data.strength.longMedium.valid,"stale M5 source is not displayed as current ranks");
        strength.pairRankInfo.m5BarTime=strength.targetM5BarTime;strength.pairRankInfo.baseLongMediumTermAverageRank=0;
        ElliotPanelLiveAdapter.build(all,strength,true,"加重",data);
        Check(data.strength.status.Contains("不正") && !data.strength.longMedium.valid,"invalid ranks are distinguished from neutral ranks");
        strength.status=-1;ElliotPanelLiveAdapter.build(all,strength,true,"加重",data);
        Check(data.strength.status=="読取失敗","read error stays explicit");
        ElliotPanelLiveAdapter.build(all,strength,false,"加重",data);
        Check(!data.strength.enabled && data.strength.status=="通貨強弱OFF","disabled strength clears previously available values");
        first.wave=null;ElliotPanelLiveAdapter.build(all,strength,false,"加重",data);
        Check(data.frames[1].row.timeFrameLabel=="M1" && !data.frames[1].row.hasData && data.frames[1].extraCount==0,"missing wave keeps its timeframe but clears stale details");
        all.tradeTimeInfo.jstTime=0;ElliotPanelLiveAdapter.build(all,strength,false,"加重",data);
        Check(data.headerTime.StartsWith("分析 SRV "),"unknown JST uses labelled server time");
        all.tradeTimeInfo.serverTime=0;ElliotPanelLiveAdapter.build(all,strength,false,"加重",data);
        Check(data.headerTime=="分析時刻 未取得","unknown time is not epoch");
        all.elliotList.values=new Elliot[0];
        Check(!ElliotPanelLiveAdapter.build(all,strength,false,"加重",data) && data.rowCount==0,"empty analysis clears old rows");
        return "PASS "+checks+" live panel assertions";
    }
}
'''
        self.assertRegex(run_csharp(source, "[LivePanelFixture]::Run()\n"), r"PASS \d+ live panel assertions")


class ElliotPanelSavedTests(unittest.TestCase):
    def test_saved_record_adapter_keeps_seven_frames_capture_times_missing_data_and_navigation(self):
        source = ("using System;using System.Globalization;using System.Collections.Generic;using System.Linq;\n"
                  + API + table_fixture() + panel_data_fixture() + frame_fixture() + strength_fixture())
        source += r'''
public class M5ObservationHistoryRecord {
    public long id=1,runId=17,barTime=1795500000,jstTime=1795525200,captureTime=1795500012;
    public bool isPreviousRun;
    public M5ObservationHistoryFrame[] frames=new M5ObservationHistoryFrame[7];
    public M5ObservationHistoryStrength strength=new M5ObservationHistoryStrength();
    public M5ObservationHistoryRecord() {
        int[] periods={49153,32769,16408,16388,16385,15,5};
        for(int i=0;i<7;i++) frames[i]=new M5ObservationHistoryFrame { timeFrame=periods[i] };
    }
}
public class SavedPanelStub : MqlApi {
    public int shows;public ElliotPanelData shown;
    public bool showSaved(ElliotPanelData data) { shows++;shown=Clone(data);return true; }
}
public class SavedPanelFixture : MqlApi {
    long chartId=0,selectedTime,hoverTime=1795499700;
    string prefix="Markers-";
    int markerCount=3,checks;
    int[] markerIndexes={0,1,2};
    ElliotPanelData savedPanelData=new ElliotPanelData();
    SavedPanelStub panel=new SavedPanelStub();
    static string ChartSymbol(long chart) { return "USDJPY"; }
    void Check(bool value,string message) { checks++;if(!value) throw new Exception(message); }
    public string Run() {
        M5ObservationHistoryRecord record=new M5ObservationHistoryRecord();
        foreach(M5ObservationHistoryFrame frame in record.frames) {
            frame.hasData=true;frame.mainWave="3";frame.isUptrend=0;frame.isBuy=1;
            frame.isAdded=0;frame.isConfirmed=1;frame.hasPointRate=true;frame.pointRate=0;
            frame.pointTime=1795499700;frame.pointJstTime=1795524900;
            frame.gmmaTrendCount=-1;frame.hasGmmaTrendCount=true;frame.gmmaCrossCount=0;frame.hasGmmaCrossCount=true;
        }
        record.strength.enabled=true;record.strength.status="取得済み";record.strength.sourceMode="TESTER";
        record.strength.weightLabel="加重";record.strength.baseCurrency="USD";record.strength.quoteCurrency="JPY";
        record.strength.longMedium.valid=true;record.strength.longMedium.baseRank=2;record.strength.longMedium.quoteRank=7;
        record.strength.longMedium.gap=5;record.strength.longMedium.comparable=true;record.strength.longMedium.delta=-2;
        M5ObservationHistoryRecord previous=new M5ObservationHistoryRecord { barTime=record.barTime-900 },
            next=new M5ObservationHistoryRecord { barTime=record.barTime+300 };
        M5ObservationHistoryRecord[] records={previous,record,next};
        ElliotPanelData converted=new ElliotPanelData();
        converted.canPrevious=true;converted.canNext=true;converted.frames[7].extraCount=1;
        ResetCounts();
        ElliotPanelSavedAdapter.build(record,"EURUSD",5,converted);
        Check(converted.symbolName=="EURUSD" && converted.digits==5 && converted.savedTime==record.barTime,"adapter uses supplied symbol and digits without chart lookup");
        Check(converted.rowCount==7 && !converted.canPrevious && !converted.canNext && converted.frames[7].extraCount==0,"adapter clears prior state and leaves navigation to drawer");
        Check(CreateCalls==0 && DeleteCalls==0 && BulkDeleteCalls==0 && RedrawCalls==0,"saved conversion has no drawing side effects");
        showRecord(records,1,3);
        ElliotPanelData shown=panel.shown;
        Check(panel.shows==1 && shown.symbolName=="USDJPY" && shown.digits==3 && shown.savedTime==record.barTime,"selected saved record reaches the shared panel");
        Check(shown.rowCount==7 && shown.frames[6].timeFrame==PERIOD_M5 && shown.frames[6].row.timeFrameLabel=="M5","seven saved frames retain timeframe identity without a fabricated M1");
        Check(shown.headerTime.StartsWith("観測 JST ") && shown.metadata.StartsWith("Run 17 / 取得 SRV ") && shown.metadata.Contains("Run 17") && shown.metadata.Contains("ID 1"),"observation and capture timestamps are distinct and source metadata retained");
        Check(shown.frames[6].pointTime==record.frames[6].pointTime && shown.frames[6].pointJstTime==record.frames[6].pointJstTime,"saved point timestamps are copied without conversion or reanalysis");
        Check(shown.frames[6].row.hasPointRate && shown.frames[6].row.pointRate==0,"saved zero price remains recorded");
        Check(shown.frames[6].row.hasGmmaTrendCount && shown.frames[6].row.gmmaTrendCount==-1 && shown.frames[6].row.hasGmmaCrossCount && shown.frames[6].row.gmmaCrossCount==0,"saved adapter preserves negative-one and recorded-zero GMMA values with availability");
        Check(shown.frames[6].extraCount==0 && StringLen(shown.frames[6].movementTooltip)==0,"unsaved extras and live-only movement metrics are not invented");
        Check(shown.strength.title.Contains("同M5") && shown.strength.title.Contains("TESTER") && shown.strength.tooltip.Contains("保存時点の値とは限りません"),"same-M5 historical strength source is explicit");
        Check(shown.strength.longMedium.valid && shown.strength.longMedium.comparable && shown.strength.longMedium.gap==5 && shown.strength.longMedium.delta==-2,"saved ranks preserve independent gap and delta");
        Check(shown.canPrevious && shown.canNext && shown.hint.Contains("前まで 15分"),"visible navigation availability and gaps copied");
        Check(selectedTime==record.barTime && hoverTime==0,"opening panel updates marker selection and dismisses compact hover");
        record.isPreviousRun=true;record.runId=12;showRecord(records,1,3);
        Check(panel.shown.metadata.StartsWith("過去Run補完 / Run 12 / "),"supplemented record displays actual source Run before capture details");
        Check(panel.shown.rowCount==7 && panel.shown.canPrevious && panel.shown.canNext,"previous Run remains fully viewable and navigable");
        Check(ElliotPanelSavedAdapter.sourceText(record)=="過去Run補完 / Run 12","hover and details share source label");
        record.isPreviousRun=false;record.runId=17;showRecord(records,1,3);
        Check(!panel.shown.metadata.Contains("補完") && panel.shown.metadata.StartsWith("Run 17 / "),"replacement with target Run removes stale supplement label");
        record.frames[6].hasPointRate=false;record.frames[5].hasData=false;
        record.frames[6].hasGmmaCrossCount=false;
        record.jstTime=0;record.captureTime=0;showRecord(records,1,3);
        Check(panel.shown.headerTime.StartsWith("観測 SRV ") && panel.shown.metadata.Contains("取得 SRV 未記録"),"unknown saved JST/capture time uses explicit fallback rather than epoch");
        Check(!panel.shown.frames[6].row.hasPointRate && !panel.shown.frames[5].row.hasData,"missing metrics and whole saved timeframe remain unknown");
        Check(!panel.shown.frames[6].row.hasGmmaCrossCount && ElliotTableFormatter.gmmaCellText(panel.shown.frames[6].row,1)=="?","saved adapter preserves missing GMMA even when its stored numeric field is zero");
        markerCount=0;updatePanelNavigation(records);
        Check(!savedPanelData.canPrevious && !savedPanelData.canNext,"no drawn records disables both navigation directions without replacing snapshot");
        record.id=0;showRecord(records,1,3);
        Check(panel.shown.rowCount==0 && panel.shown.status.Contains("記録はありません") && !panel.shown.frames[6].row.hasData,"missing observation clears prior saved table and details");
        return "PASS "+checks+" saved panel adapter assertions";
    }
'''
        methods = extracted_methods(DRAWER.read_text(encoding="utf-8-sig"), (
            "showRecord", "updatePanelNavigation", "findAdjacentRecordIndex", "navigationGapText",
        ))
        source += methods + "}\npublic class ElliotPanelSavedAdapter : MqlApi {\n"
        source += extracted_methods(SAVED_ADAPTER.read_text(encoding="utf-8-sig"), (
            "build", "sourceText",
            "fillPanelStrength", "fillPanelStrengthPeriod", "strengthTitle", "strengthStatusText",
            "fillTableRow", "frameName", "timeText",
        )) + "}\n"
        self.assertRegex(run_csharp(source, "(New-Object SavedPanelFixture).Run()\n"),
                         r"PASS \d+ saved panel adapter assertions")


if __name__ == "__main__":
    unittest.main(verbosity=2)
