//+------------------------------------------------------------------+
//|                                            VolatilitySqueeze.mq4 |
//|                                            Copyright 2019, t04st |
//|                                                        t04st.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2019, t04st"
#property link      "t04st.com"
#property version   "1.00"
#property strict
#property indicator_separate_window

#property indicator_height 300
#property indicator_minimum -5
#property indicator_maximum 105
#property indicator_buffers 3
#property indicator_color1 Blue
#property indicator_color2 Red
#property indicator_color3 Pink

//---- Input params
extern int RSILen    =14;         
extern int KLen      =3;         
extern int DLen      =2;         
extern int Slowing   =2;         
extern int StochOB   =90;         
extern int StochOS   =10;         

#include <utility.mqh>           // MUST go below input parameters


//---= Buffers
double StochRSIBuf[];
double SigBuf[];
double RSIBuf[];

//--- Globals
bool initHasRun      = false;
int RPrice           = 5;
int subwindow_idx    = NULL;
int id               = 0;
string indicator     = "Volatility Squeeze";
string signal        = "Signal";
string lowerband     = "Oversold Level";
string upperband     = "Overbought Level";

// buffers
double ExtATRBuffer[];

sinput int len = 14;
sinput int osc_shortlen = 5;
sinput int osc_longlen = 10;
const int smoothK = 3;
const int smoothD = 3;
const int lengthRSI = 14;
const int lengthStoch = 14;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- indicator buffers mapping
   //SetIndexStyle(0,DRAW_LINE);
   //SetIndexBuffer(0,ExtATRBuffer);
//---
   
   IndicatorBuffers(3);
   IndicatorShortName(indicator);
   IndicatorDigits(1);
   
   SetIndexLabel(0,indicator);
   SetIndexStyle(0,DRAW_LINE,STYLE_SOLID,1, clrBlue);
   SetIndexBuffer(0, StochRSIBuf);
   ArraySetAsSeries(StochRSIBuf,false);
   ArrayInitialize(StochRSIBuf,0);
   SetIndexDrawBegin(0,KLen+Slowing);
 
   SetIndexLabel(1,signal);
   SetIndexStyle(1,DRAW_LINE,STYLE_SOLID,1, clrOrange);
   SetIndexBuffer(1, SigBuf);
   ArraySetAsSeries(SigBuf,false);
   ArrayInitialize(SigBuf,0);
   SetIndexDrawBegin(1,KLen+Slowing+DLen);
   SetIndexShift(1, Slowing*-1);
   
   SetIndexLabel(2,"RSI");
   SetIndexStyle(2,DRAW_LINE,STYLE_DOT,1, clrBlack);
   SetIndexBuffer(2, RSIBuf);   
   ArraySetAsSeries(RSIBuf,false);
   ArrayInitialize(RSIBuf,0);
   SetIndexDrawBegin(2,RSILen);  
  
   // upper/lower bands
   subwindow_idx=ChartWindowFind(id, indicator);
   if(subwindow_idx==-1)
      subwindow_idx=0;
   int res = ObjectCreate(id, lowerband, OBJ_HLINE, subwindow_idx, 0, StochOS);
   ObjectSetInteger(id, lowerband, OBJPROP_COLOR, clrBlack); 
   ObjectSetInteger(id, lowerband, OBJPROP_STYLE, 1); 
   ObjectSetInteger(id, lowerband, OBJPROP_WIDTH, 1); 
   ObjectSetInteger(id, lowerband, OBJPROP_BACK, false); 
   ObjectSetInteger(id, lowerband, OBJPROP_SELECTABLE, true); 
   ObjectSetInteger(id, lowerband, OBJPROP_SELECTED, true); 
   ObjectSetInteger(id, lowerband, OBJPROP_HIDDEN, false); 
   ObjectSetInteger(id, lowerband, OBJPROP_ZORDER, 0); 
   res = ObjectCreate(id, upperband, OBJ_HLINE, subwindow_idx, 0, StochOB);
   ObjectSetInteger(id, upperband, OBJPROP_COLOR, clrBlack); 
   ObjectSetInteger(id, upperband, OBJPROP_STYLE, 1); 
   ObjectSetInteger(id, upperband, OBJPROP_WIDTH, 1); 
   ObjectSetInteger(id, upperband, OBJPROP_BACK, false); 
   ObjectSetInteger(id, upperband, OBJPROP_SELECTABLE, true); 
   ObjectSetInteger(id, upperband, OBJPROP_SELECTED, true); 
   ObjectSetInteger(id, upperband, OBJPROP_HIDDEN, false); 
   ObjectSetInteger(id, upperband, OBJPROP_ZORDER, 0); 
 
   log("StochRSI initialized. Externs: [RSILen:"+(string)RSILen+", KLen:"+(string)KLen
      +" DLen:"+(string)DLen+", Slowing:"+(string)Slowing+", StochOB:"+(string)StochOB
      +", StochOS:"+(string)StochOS);
   initHasRun=true;


   return(INIT_SUCCEEDED);
  }
  
void OnDeinit(const int reason) {   
   log("StochRSI Deinit(). IsTesting:"+IsTesting());
  
   if(!IsTesting()) {
      ObjectDelete(0, upperband);
      ObjectDelete(0, lowerband);
      ObjectsDeleteAll();
   }
   
   //RSILen=0;
   //KLen=0;
   //DLen=0;
   //Slowing=0;
   //StochOB=0;
   //StochOS=0;
 
   return;
}
//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
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
// ATR

   int counted_bars = IndicatorCounted();
   int i;

   i = Bars - counted_bars - 1;
   //i = MathMin(i, 300);
   
   double atr_short[];
   double atr_long[];

   while (i > 0) {
      ArrayResize(atr_short, ArraySize(atr_short)+1);
      ArrayResize(atr_long, ArraySize(atr_long)+1);
 
      atr_short[ArraySize(atr_short)-1] = iATR(NULL, 0, 14, i);
      atr_long[ArraySize(atr_long)-1] = iATR(NULL, 0, 14, i);
 
      i--;
   }
   
   double atr_short_ema[];
   double atr_long_ema[];
   
   for (int i = 0; i < ArraySize(atr_short); i++) {
      ArrayResize(atr_short_ema, ArraySize(atr_short_ema)+1);
      atr_short_ema[ArraySize(atr_short_ema)-1] = iMAOnArray(atr_short, 0, osc_shortlen, 0, MODE_EMA, i);
      ArrayResize(atr_long_ema, ArraySize(atr_long_ema)+1);
      atr_long_ema[ArraySize(atr_long_ema)-1] = iMAOnArray(atr_long, 0, osc_longlen, 0, MODE_EMA, i);
   }
   
   double osc[];
   ArrayResize(osc, ArraySize(atr_short_ema));
   
   for (int i = 0; i < ArraySize(atr_short_ema); i++) {
      //debuglog("atr_short[" + i + "] = " + atr_short[i]);
      //debuglog("atr_long[" + i + "] = " + atr_long[i]);
      if (atr_long_ema[i] == 0.0) {
         osc[i] = 0.0;
      } else {
         osc[i] = 100.0 * ((atr_short_ema[i] - atr_long_ema[i]) / atr_long_ema[i]);
      }
   }
   
   
   double low_osc=0, high_osc=0, sum_K=0;
   int iTSBar, iBar;
   
   if(prev_calculated==0) {
      iBar = MathMin(KLen+Slowing, RSILen);
      ArrayInitialize(StochRSIBuf,0);
      ArrayInitialize(SigBuf,0);
      ArrayInitialize(RSIBuf,0);
   }
   else {
      iBar = prev_calculated; // last bar becomes new index
   }
     
   
   // iBar: non-Timeseries (left-to-right) index
   for(; iBar<rates_total; iBar++) {  
      iTSBar=Bars-iBar-1;  
      sum_K=0;    
      double osc_val=osc[iTSBar];
      RSIBuf[iBar]=osc_val;
      high_osc=osc_val;
      low_osc=osc_val;
      
      // K,D calculations
      for(int x=1;x<=KLen;x++){
         low_osc=MathMin(low_osc,osc[iTSBar+x]);
         high_osc=MathMax(high_osc,osc[iTSBar+x]);
      }
      for(int x=1;x<=DLen;x++){
         sum_K=sum_K + StochRSIBuf[iBar-x];
      }
      
      // StochRSI=(RSI-LowestRSI)/(HighestRSI-LowestRSI)
      if(high_osc - low_osc > 0)
         StochRSIBuf[iBar] = ((osc_val-low_osc)/(high_osc-low_osc))*100;
      else
         StochRSIBuf[iBar] = 100;
         
      SigBuf[iBar]=sum_K/DLen;
   }
   
   

   //for (int i = 0; i < ArraySize(osc); i++) {
   //   ExtATRBuffer[i] = osc[i];//atr_long_ema[i];//ArraySize(atr_short_ema)-i-1];
   //}
   
   return(rates_total);
  }
//+------------------------------------------------------------------+
//| ChartEvent function                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
//---
   
  }
//+------------------------------------------------------------------+
