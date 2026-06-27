#property copyright "Compile test"
#property version   "1.01"
#property description "A simple moving-average indicator for compile testing."
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1

#property indicator_label1  "Test MA"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

input int InpPeriod = 14;

double IndicatorBuffer[];

int OnInit() {
   if(InpPeriod < 1)
      return(INIT_PARAMETERS_INCORRECT);

   SetIndexBuffer(0,IndicatorBuffer,INDICATOR_DATA);
   PlotIndexSetInteger(0,PLOT_DRAW_BEGIN,InpPeriod-1);
   IndicatorSetString(INDICATOR_SHORTNAME,
                      "Compile Test MA ("+IntegerToString(InpPeriod)+")");

   return(INIT_SUCCEEDED);
  }

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < InpPeriod)
      return(0);

   int start=(prev_calculated > InpPeriod) ? prev_calculated-1 : InpPeriod-1;

   if(prev_calculated == 0)
      ArrayInitialize(IndicatorBuffer,EMPTY_VALUE);

   for(int i=start; i<rates_total; i++)
     {
      double sum=0.0;
      for(int j=0; j<InpPeriod; j++)
         sum+=close[i-j];

      IndicatorBuffer[i]=sum/InpPeriod;
     }

   return(rates_total);
  }
