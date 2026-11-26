"""Exercise the production shared Elliott panel with a small MQL API substitute.

The syntax adapter preserves panel state and layout branches. Only MT5's chart
object API and font metrics are substituted; native compilation is checked
separately with MetaEditor.
"""

import re
import unittest

from test_m5_observation_history_reader import (
    ROOT, block_end, code_only, method, run_csharp, table_fixture, extracted_methods,
    table_layout_fixture, frame_fixture, strength_fixture, DRAWER,
)


DRAW = ROOT / "Include/Mstng/Draw"


def syntax(source):
    """Adapt MQL scalar/reference/array syntax without changing branches."""
    source = re.sub(r"\bconst\s+", "", source)
    source = re.sub(r"\b(datetime|color|ENUM_ELLIOT_PANEL_ACTION|ENUM_TIMEFRAMES)\b",
                    lambda match: "long" if match[1] == "datetime" else "int", source)
    source = source.replace("::", ".").replace("NULL", "null")
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


API = r'''
public class MqlApi {
    public const int PERIOD_CURRENT=0,PERIOD_M1=1,PERIOD_M5=5,PERIOD_M15=15,PERIOD_H1=16385,
        PERIOD_H4=16388,PERIOD_D1=16408,PERIOD_W1=32769,PERIOD_MN1=49153;
    public const int clrSilver=1,clrWhite=2,clrAqua=3,clrHotPink=4,clrDodgerBlue=5,clrMagenta=6,
        clrDeepSkyBlue=7,clrPlum=8,clrSlateGray=9,clrWhiteSmoke=10,clrGray=11,clrGold=12;
    public const int OBJ_LABEL=1,OBJ_RECTANGLE_LABEL=2,OBJ_BUTTON=3,CORNER_LEFT_UPPER=0,
        ANCHOR_LEFT_UPPER=0,BORDER_FLAT=0;
    public const int OBJPROP_CORNER=1,OBJPROP_ANCHOR=2,OBJPROP_XDISTANCE=3,OBJPROP_YDISTANCE=4,
        OBJPROP_COLOR=5,OBJPROP_FONTSIZE=6,OBJPROP_BACK=7,OBJPROP_SELECTABLE=8,OBJPROP_HIDDEN=9,
        OBJPROP_ZORDER=10,OBJPROP_FONT=11,OBJPROP_TEXT=12,OBJPROP_TOOLTIP=13,OBJPROP_XSIZE=14,
        OBJPROP_YSIZE=15,OBJPROP_BGCOLOR=16,OBJPROP_BORDER_TYPE=17,OBJPROP_SELECTED=18,
        OBJPROP_STATE=19,OBJPROP_BORDER_COLOR=20;
    public const int CHART_WIDTH_IN_PIXELS=1,CHART_HEIGHT_IN_PIXELS=2;
    public static int Width=1400,Height=800;
    public class ChartObject {
        public int kind;
        public Dictionary<int,long> numbers=new Dictionary<int,long>();
        public Dictionary<int,string> texts=new Dictionary<int,string>();
    }
    public static Dictionary<string,ChartObject> Objects=new Dictionary<string,ChartObject>();
    public static string FailName="";
    public static long ChartGetInteger(long chart,int property,int subwindow=0) {
        return property==CHART_WIDTH_IN_PIXELS ? Width : Height;
    }
    public static int ObjectFind(long chart,string name) { return Objects.ContainsKey(name) ? 0 : -1; }
    public static bool ObjectCreate(long chart,string name,int kind,int subwindow,long time,double price) {
        if(name==FailName) return false;
        if(!Objects.ContainsKey(name)) Objects.Add(name,new ChartObject { kind=kind });
        return true;
    }
    public static bool ObjectSetInteger(long chart,string name,int property,long value) {
        if(!Objects.ContainsKey(name)) return false;Objects[name].numbers[property]=value;return true;
    }
    public static bool ObjectSetInteger(long chart,string name,int property,bool value) {
        return ObjectSetInteger(chart,name,property,value ? 1L : 0L);
    }
    public static bool ObjectSetString(long chart,string name,int property,string value) {
        if(!Objects.ContainsKey(name)) return false;Objects[name].texts[property]=value;return true;
    }
    public static int ObjectsDeleteAll(long chart,string prefix,int subwindow=0,int type=-1) {
        string[] names=Objects.Keys.Where(value=>value.StartsWith(prefix,StringComparison.Ordinal)).ToArray();
        foreach(string name in names) Objects.Remove(name);return names.Length;
    }
    public static bool ObjectDelete(long chart,string name) { return Objects.Remove(name); }
    public static void ChartRedraw(long chart=0) {}
    public static int MathMin(int first,int second) { return Math.Min(first,second); }
    public static int MathMax(int first,int second) { return Math.Max(first,second); }
    public static double MathMax(double first,double second) { return Math.Max(first,second); }
    public static int ArraySize<T>(T[] values) { return values.Length; }
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


class ElliotPanelViewTests(unittest.TestCase):
    def panel_source(self):
        return ("using System;using System.Globalization;using System.Collections.Generic;using System.Linq;\n"
                + API + table_fixture() + panel_data_fixture() + table_renderer_fixture() + panel_fixture())

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
        string[] liveNames=Objects.Keys.Where(name=>name.StartsWith("Panel-Row5-Elliot",StringComparison.Ordinal)).OrderBy(name=>name).ToArray();
        ElliotPanelData saved=Data("USDJPY",true);saved.frames[6].row=Clone(row);
        panel.showSaved(saved);
        string[] savedNames=Objects.Keys.Where(name=>name.StartsWith("Panel-Row5-Elliot",StringComparison.Ordinal)).OrderBy(name=>name).ToArray();
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
        self.assertRegex(run_csharp(source, "[PanelFixture]::Run()\n"), r"PASS \d+ split panel assertions")

    def test_split_elliot_renderer_fits_the_full_576_pixel_region_and_retains_long_tooltips(self):
        source = self.panel_source() + PANEL_SETUP + r'''
    public static string Run() {
        ElliotTableRowData row=new ElliotTableRowData { hasData=true,mainWave="3",subWave=new string('i',24),
            originalWave="5",isUptrend=0,isBuy=1,isConfirmed=0,isAdded=1,previousMotiveSubElliotIndex=3,
            originalWaveIndex=5,hasPointFibonacciExpansionPercent=true,pointFibonacciExpansionPercent=161.8,
            hasPointPipsDiff=true,pointPipsDiff=-12.5,hasPointRate=true,pointRate=159.234 };
        ElliotTablePalette palette=new ElliotTablePalette();ElliotTableLayout layout=new ElliotTableLayout();
        layout.originX=40;layout.originY=70;layout.columnXs[4]=400;layout.columnWidths[4]=576;
        layout.paddingX=8;layout.paddingY=3;layout.clipText=true;layout.showSeparators=true;layout.splitElliot=true;
        for(int i=0;i<4;i++) layout.columnVisible[i]=false;
        Check(DrawElliotTable.drawHeader(0,"Header-",layout) && DrawElliotTable.drawRow(0,"Row-",row,3,palette,layout),"576-pixel split area draws header and row");
        string[] keys={"Direction","MainWave","SubWave","OriginalWave","Confirmed","Added","PreviousSub","Fibonacci","Pips","Price"};
        int[] widths={44,44,48,44,60,44,44,98,72,78};
        long start=Number("Row-ElliotDirection",OBJPROP_XDISTANCE),position=start;
        for(int i=0;i<keys.Length;i++) {
            string name="Row-Elliot"+keys[i];
            Check(Number(name,OBJPROP_XDISTANCE)==position,"successive cell position matches allocated width: "+keys[i]);
            Check(Number("Header-Elliot"+keys[i],OBJPROP_XDISTANCE)==position,"header aligns with its data cell: "+keys[i]);
            Check(Text(name).Length*8<=widths[i],"measured text stays inside subcolumn: "+keys[i]);
            Check(Number(name,OBJPROP_YDISTANCE)==73 && Number(name,OBJPROP_FONTSIZE)==11,"split labels retain row position and font");
            position+=widths[i];
        }
        Check(position-start==576 && Number("Row-ElliotPrice",OBJPROP_XDISTANCE)+Text("Row-ElliotPrice").Length*8<=40+400+576,"final price text stays inside the complete 576-pixel region");
        Check(Text("Row-ElliotSubWave").EndsWith("…") && Objects["Row-ElliotSubWave"].texts[OBJPROP_TOOLTIP].Contains(row.subWave),"long subwave is clipped but complete value remains in tooltip");
        Check(!Objects.ContainsKey("Row-Elliot") && !Objects.ContainsKey("Header-Elliot"),"split rendering creates no overlapping composite wave label");
        ElliotTableLayout legacy=new ElliotTableLayout();legacy.columnXs[4]=400;legacy.columnWidths[4]=576;
        for(int i=0;i<4;i++) legacy.columnVisible[i]=false;
        Check(!legacy.splitElliot && DrawElliotTable.drawRow(0,"Legacy-",row,3,palette,legacy),"nonpanel callers keep original default layout");
        Check(Text("Legacy-Elliot").Contains("▼3."+row.subWave) && !Objects.ContainsKey("Legacy-ElliotMainWave"),"legacy chart table retains its composite wave text");
        FailName="Failed-ElliotSubWave";
        Check(!DrawElliotTable.drawRow(0,"Failed-",row,3,palette,layout) && Objects.ContainsKey("Failed-ElliotPrice"),"split-cell creation failure is reported while later cells still draw");
        return "PASS "+checks+" split renderer assertions";
    }
}
'''
        self.assertRegex(run_csharp(source, "[PanelFixture]::Run()\n"), r"PASS \d+ split renderer assertions")

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
        self.assertRegex(run_csharp(source, "[PanelFixture]::Run()\n"), r"PASS \d+ shared panel state assertions")

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
        Check(Number("Panel-Background",OBJPROP_XDISTANCE)+Number("Panel-Background",OBJPROP_XSIZE)<=Width && Number("Panel-Background",OBJPROP_YDISTANCE)+Number("Panel-Background",OBJPROP_YSIZE)<=Height,"panel frame fits chart bounds");
        Width=400;Height=220;panel.draw();
        Check(Objects.ContainsKey("Panel-Small") && !Objects.ContainsKey("Panel-Row5-TimeFrame"),"narrow chart shows explicit list size message");
        Check(Objects.ContainsKey("Panel-Live") && Objects.ContainsKey("Panel-Close") && Objects.ContainsKey("Panel-Expand"),"narrow chart keeps return, close and fold controls available");
        foreach(string key in new string[]{"Live","Close","Expand","Previous","Next"}) {
            Check(Number("Panel-"+key,OBJPROP_XDISTANCE)>=0 && Number("Panel-"+key,OBJPROP_XDISTANCE)+Number("Panel-"+key,OBJPROP_XSIZE)<=Width,"narrow button inside chart: "+key);
        }
        Width=1400;Height=800;FailName="Panel-Title";
        Check(!panel.draw() && Objects.ContainsKey("Panel-Close"),"drawing failure reported without suppressing remaining controls");
        FailName="";saved.rowCount=0;saved.status="このM5時刻の記録はありません。";
        panel.showSaved(saved);
        Check(Text("Panel-Empty").Contains("記録はありません") && Objects.ContainsKey("Panel-Live") && !Objects.ContainsKey("Panel-Row5-TimeFrame"),"missing observation keeps navigation and explanation without invented rows");
        return "PASS "+checks+" shared panel layout assertions";
    }
}
'''
        self.assertRegex(run_csharp(source, "[PanelFixture]::Run()\n"), r"PASS \d+ shared panel layout assertions")


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
        Check(data.frames[1].extraCount==7 && data.frames[1].extraValues[0]=="SMO fixture" && data.frames[1].extraColors[0]==42,"existing stochastic order text and color copied");
        Check(data.frames[1].extraValues[1]=="+2" && data.frames[1].extraValues[2]=="-3" && data.frames[1].extraValues[3]=="0","oscillator counts preserve sign and recorded zero");
        Check(data.frames[1].extraColors[1]==data.palette.upColor && data.frames[1].extraColors[2]==data.palette.downColor && data.frames[1].extraColors[3]==data.palette.neutralColor,"extra indicator colors share the table palette");
        Check(data.frames[1].extraValues[6]=="A" && data.frames[1].extraColors[6]==data.palette.neutralColor,"previous corrective wave preserves its neutral color");
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
        }
        record.strength.enabled=true;record.strength.status="取得済み";record.strength.sourceMode="TESTER";
        record.strength.weightLabel="加重";record.strength.baseCurrency="USD";record.strength.quoteCurrency="JPY";
        record.strength.longMedium.valid=true;record.strength.longMedium.baseRank=2;record.strength.longMedium.quoteRank=7;
        record.strength.longMedium.gap=5;record.strength.longMedium.comparable=true;record.strength.longMedium.delta=-2;
        M5ObservationHistoryRecord previous=new M5ObservationHistoryRecord { barTime=record.barTime-900 },
            next=new M5ObservationHistoryRecord { barTime=record.barTime+300 };
        M5ObservationHistoryRecord[] records={previous,record,next};
        showRecord(records,1,3);
        ElliotPanelData shown=panel.shown;
        Check(panel.shows==1 && shown.symbolName=="USDJPY" && shown.digits==3 && shown.savedTime==record.barTime,"selected saved record reaches the shared panel");
        Check(shown.rowCount==7 && shown.frames[6].timeFrame==PERIOD_M5 && shown.frames[6].row.timeFrameLabel=="M5","seven saved frames retain timeframe identity without a fabricated M1");
        Check(shown.headerTime.StartsWith("観測 JST ") && shown.metadata.StartsWith("取得 SRV ") && shown.metadata.Contains("Run 17") && shown.metadata.Contains("ID 1"),"observation and capture timestamps are distinct and source metadata retained");
        Check(shown.frames[6].pointTime==record.frames[6].pointTime && shown.frames[6].pointJstTime==record.frames[6].pointJstTime,"saved point timestamps are copied without conversion or reanalysis");
        Check(shown.frames[6].row.hasPointRate && shown.frames[6].row.pointRate==0,"saved zero price remains recorded");
        Check(shown.frames[6].extraCount==0 && StringLen(shown.frames[6].movementTooltip)==0,"unsaved extras and live-only movement metrics are not invented");
        Check(shown.strength.title.Contains("同M5") && shown.strength.title.Contains("TESTER") && shown.strength.tooltip.Contains("保存時点の値とは限りません"),"same-M5 historical strength source is explicit");
        Check(shown.strength.longMedium.valid && shown.strength.longMedium.comparable && shown.strength.longMedium.gap==5 && shown.strength.longMedium.delta==-2,"saved ranks preserve independent gap and delta");
        Check(shown.canPrevious && shown.canNext && shown.hint.Contains("前まで 15分"),"visible navigation availability and gaps copied");
        Check(selectedTime==record.barTime && hoverTime==0,"opening panel updates marker selection and dismisses compact hover");
        record.frames[6].hasPointRate=false;record.frames[5].hasData=false;
        record.jstTime=0;record.captureTime=0;showRecord(records,1,3);
        Check(panel.shown.headerTime.StartsWith("観測 SRV ") && panel.shown.metadata.Contains("取得 SRV 未記録"),"unknown saved JST/capture time uses explicit fallback rather than epoch");
        Check(!panel.shown.frames[6].row.hasPointRate && !panel.shown.frames[5].row.hasData,"missing metrics and whole saved timeframe remain unknown");
        markerCount=0;updatePanelNavigation(records);
        Check(!savedPanelData.canPrevious && !savedPanelData.canNext,"no drawn records disables both navigation directions without replacing snapshot");
        record.id=0;showRecord(records,1,3);
        Check(panel.shown.rowCount==0 && panel.shown.status.Contains("記録はありません") && !panel.shown.frames[6].row.hasData,"missing observation clears prior saved table and details");
        return "PASS "+checks+" saved panel adapter assertions";
    }
'''
        methods = extracted_methods(DRAWER.read_text(encoding="utf-8-sig"), (
            "showRecord", "updatePanelNavigation", "findAdjacentRecordIndex", "navigationGapText",
            "fillPanelStrength", "fillPanelStrengthPeriod", "strengthTitle", "strengthStatusText",
            "fillTableRow", "frameName", "timeText",
        ))
        source += methods + "}\n"
        self.assertRegex(run_csharp(source, "(New-Object SavedPanelFixture).Run()\n"),
                         r"PASS \d+ saved panel adapter assertions")


if __name__ == "__main__":
    unittest.main(verbosity=2)
