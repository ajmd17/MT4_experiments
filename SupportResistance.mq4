#property copyright "Copyright 2019, t04st"
#property link      "t04st.com"
#property version   "1.00"
#property strict
#property indicator_chart_window

#include <FX/Draw.mqh>
#include <Arrays/ArrayDouble.mqh>
#include <Arrays/ArrayInt.mqh>

sinput int SR1_resolution = 15;
sinput bool ENABLE_REJECTION_TEST = true;
sinput int maxClosesOutsideRange = 5;
sinput int minRequiredPointsInRange = 2;
sinput bool SR1_enabled = true;
sinput bool SR2_enabled = true;
sinput double PRECISION = 3.0;

enum RejectionType {
   REJECTION_BULL,
   REJECTION_BEAR
};

class RangeRejection {
public:
   datetime x;
   double y;
   RejectionType type;
};
RangeRejection* rejections[];

enum PointDirection {
   POINT_DIR_DOWN,
   POINT_DIR_UP
};

enum SwingType {
   HIGHER_HIGH,
   HIGHER_LOW,
   LOWER_HIGH,
   LOWER_LOW,
   EQUAL_HIGH,
   EQUAL_LOW,
};

class FractalPoint {
public:
   datetime time;
   int index;
   double val;
   double atr;
   PointDirection dir;
   SwingType swingType;
   
   static bool InRange(FractalPoint* a, FractalPoint* b) {
      return MathAbs(a.val - b.val) <= ((a.atr + b.atr) / 2.0) * (1/PRECISION);
   }
};
FractalPoint* pts[];


class PointCluster {
public:
   double avg;
   double lowerBound;
   double upperBound;
};

class RangeRect {
public:
   datetime startTime;
   datetime endTime;
   double rangeLow;
   double rangeHigh;
};
RangeRect* rangeRects[];


class Jenks {
public:
   int run(double &data[], int n_classes, double &output[]) {
      if (n_classes > ArraySize(data)) return 1;
      
      ArraySort(data);
      CArrayInt lower_class_limits[];
      CArrayDouble variance_combinations[];
      jenks_getMatrices(data, n_classes, lower_class_limits, variance_combinations);
      jenks_getBreaks(data, n_classes, lower_class_limits, output);
      return 0;
   }

private:
   void jenks_getMatrices(double &data[], int n_classes, CArrayInt &lower_class_limits[], CArrayDouble &variance_combinations[]) {
      //CArrayDouble lower_class_limits[];
      //CArrayDouble variance_combinations[];
      double variance = 0.0;
      // this could be optimized b/c we know array size in advance
      for (int i = 0; i < ArraySize(data) + 1; i++) {
         CArrayInt tmp1;
         CArrayDouble tmp2;
         
         for (int j = 0; j < n_classes + 1; j++) {
            tmp1.Add(0);
            tmp2.Add(0.0);
         }
         ArrayResize(lower_class_limits, ArraySize(lower_class_limits)+1);
         lower_class_limits[ArraySize(lower_class_limits)-1] = tmp1;
         ArrayResize(variance_combinations, ArraySize(variance_combinations)+1);
         variance_combinations[ArraySize(variance_combinations)-1] = tmp2;
      }
      
      for (int i = 1; i < n_classes + 1; i++) {
         lower_class_limits[1].Update(i, 1);
         variance_combinations[1].Update(i, 0.0);
         
         for (int j = 2; j < ArraySize(data) + 1; j++) {
            variance_combinations[j].Update(i, -MathLog(0));
         }
      }
      
      for (int l = 2; l < ArraySize(data) + 1; l++) {
         double sum = 0.0;
         double sum_squares = 0.0;
         int w = 0;
         int i4 = 0;
         
         for (int m = 1; m < l + 1; m++) {
         
            int lower_class_limit = l - m + 1;
            double val = data[lower_class_limit - 1];
            
            w++;
            sum += val;
            sum_squares += val * val;
            variance = sum_squares - (sum * sum / w);
            i4 = lower_class_limit - 1;
            
            if (i4 == 0) continue;
            
            for (int j = 2; j < n_classes + 1; j++) {
               double v = variance + variance_combinations[i4][j - 1];
               if (variance_combinations[l][j] >= v) {
                  lower_class_limits[l].Update(j, lower_class_limit);
                  variance_combinations[l].Update(j, v);
                  //debuglog("variance_combinations[" + (string)l + "][" + (string)j + "] = " + (string)variance_combinations[l][j]);
               }
            }
         }
         
         lower_class_limits[l].Update(1, 1);
         variance_combinations[l].Update(1, variance);
      }
   }
   
   void jenks_getBreaks(double &data[], int n_classes, CArrayInt &lower_class_limits[], double &output[]) {
      int k = ArraySize(data) - 1;
      ArrayResize(output, n_classes+1);
   
      output[n_classes] = data[ArraySize(data)-1];
      output[0] = data[0];
      
      int i = n_classes;
      while (i > 1) {
         output[i - 1] = data[lower_class_limits[k][i] - 2];
         k = lower_class_limits[k][i] - 1;
         i--;
      }
   }
};


//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
void OnInit(void) {
   if (SR1_enabled) {
      for (int i = 0; i < SR1_resolution; i++ ) {
         CreateHLine("SR_" + (string)i, 0, 0, 0, clrBlue, STYLE_SOLID, 2);
         ObjectSet("SR_" + (string)i, OBJPROP_SELECTABLE, false);
         if (i != SR1_resolution - 1) {
            CreateHLine("SR_" + (string)i + "_ML", 0, 0, 0, clrGray, STYLE_DASH); //midline
            ObjectSet("SR_" + (string)i + "_ML", OBJPROP_SELECTABLE, false);
         }
      }
   }
}
//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   debuglog(deinit_reason(reason));

   if (SR1_enabled) {
      for (int i = 0; i < SR1_resolution; i++ ) {
         ObjectDelete(0, "SR_" + (string)i);
         
         if (i != SR1_resolution - 1) {
            ObjectDelete(0, "SR_" + (string)i + "_ML");
         }
      }
   }

   if (SR2_enabled) {
      for (int i = 0; i < ArraySize(allLevels); i++) {
         ObjectDelete(0, "SR2_" + (string)i);
      }
   }
 
   for (int i = 0; i < ArraySize(rejections); i++) {
      ObjectDelete(0, "RejectionArrow_" + (string)rejections[i].x);
      delete rejections[i];
   }

   for (int i = 0; i < ArraySize(rangeRects); i++) {
      ObjectDelete(0, "RangeRect_" + (string)rangeRects[i].startTime + (string)i);
      delete rangeRects[i];
   }

   for (int i = 0; i < ArraySize(pts); i++) {
      delete pts[i];
   }
}

class Range {
public:
   double rangeLow;
   double rangeMid;
   double rangeHigh;
};

enum LookbackMode {
   LOOKBACK_GT,
   LOOKBACK_LT,
   LOOKBACK_GTE,
   LOOKBACK_LTE
};

bool CheckLookback(int startIndex, LookbackMode mode, double value, int lookback=2/* amount to be considered*/) {
   int count = 0;

   while (count < lookback) {
      if (mode == LOOKBACK_GT) {
         if (High[startIndex-count] > value) return true;
      } else if (mode == LOOKBACK_GTE) {
         if (High[startIndex-count] >= value) return true;
      } else if (mode == LOOKBACK_LT) {
         if (Low[startIndex-count] < value) return true;
      } else if (mode == LOOKBACK_LTE) {
         if (Low[startIndex-count] <= value) return true;
      }
   
      count++;
   }
   
   return false;
}

Range* FindCurrentRange(Range* &ranges[], double price) {
   for (int i = 0; i < ArraySize(ranges); i++) {
      if (price >= ranges[i].rangeLow && price <= ranges[i].rangeHigh) {
         return ranges[i];
      }
   }

   return NULL;
}

void RejectionTest(Range* &levels[]) {
   int counted_bars = IndicatorCounted();
   int i = Bars - counted_bars - 1;
 
   while (i > 0) {
      RangeRejection* rej = NULL;
 
      for (int j = 0; j < ArraySize(levels); j++) {
      
         /*if (CheckLookback(i, LOOKBACK_GTE, levels[j].rangeHigh) && Close[i] < levels[j].rangeMid && Close[i+1] < levels[j].rangeMid) {
            rej = new RangeRejection;
            rej.x = Time[i];
            rej.y = levels[j].rangeHigh;
            rej.type = REJECTION_BEAR;
            break;
         }
         if (CheckLookback(i, LOOKBACK_GTE, levels[j].rangeMid) && Close[i] < levels[j].rangeLow && Close[i+1] < levels[j].rangeLow) {
            rej = new RangeRejection;
            rej.x = Time[i];
            rej.y = levels[j].rangeMid;
            rej.type = REJECTION_BEAR;
            break;
         }*/
      }
      
      if (rej != NULL) {
         ArrayResize(rejections, ArraySize(rejections) + 1);
         rejections[ArraySize(rejections)-1] = rej;
      }
      
      i--;
   }
}

void ClassifySwingTypes(FractalPoint* &pts[], FractalPoint* &highs[], FractalPoint* &lows[]) {
   // class pts by highs/lows
   for (int i = 0; i < ArraySize(pts); i++) {
      if (pts[i].dir == PointDirection::POINT_DIR_DOWN) {
         ArrayResize(highs, ArraySize(highs)+1);
         highs[ArraySize(highs)-1] = pts[i];
      } else if (pts[i].dir == PointDirection::POINT_DIR_UP) {
         ArrayResize(lows, ArraySize(lows)+1);
         lows[ArraySize(lows)-1] = pts[i];
      }
   }
   
   for (int i = 1; i < ArraySize(highs); i++) {
      if (highs[i].val > highs[i - 1].val) {
         highs[i].swingType = SwingType::HIGHER_HIGH;
      } else if (highs[i].val < highs[i - 1].val) {
         highs[i].swingType = SwingType::LOWER_HIGH;
      } else {
         highs[i].swingType = SwingType::EQUAL_HIGH;
      }
   }
 
   for (int i = 1; i < ArraySize(lows); i++) {
      if (lows[i].val > lows[i - 1].val) {
         lows[i].swingType = SwingType::HIGHER_LOW;
      } else if (lows[i].val < lows[i - 1].val) {
         lows[i].swingType = SwingType::LOWER_LOW;
      } else {
         lows[i].swingType = SwingType::EQUAL_LOW;
      }
   }
}

void DetermineMovingRanges(Range* &ranges[]) {
   int counted_bars = IndicatorCounted();
   int i = Bars - counted_bars - 1;
   
   Range* currentRange = NULL; // the current moving range
   // 3 closes outside of a range == broken??
   int outsideRangeCounter = 0;

   while (i >= 0) {
      const Range* lastRange = currentRange;
      Range* r = FindCurrentRange(ranges, Close[i]);
      
      if (r != NULL) {
         if (lastRange == NULL || r != lastRange) {
            bool newRange = lastRange == NULL;
    
            if (lastRange != NULL) {
               outsideRangeCounter++;
               if (outsideRangeCounter >= 3) {
                  outsideRangeCounter = 0;
                  newRange = true;
               }
            }
    
            if (newRange) {
               currentRange = r;
         
               RangeRect* rect = new RangeRect;
               rect.startTime = Time[i];
               rect.endTime = Time[i];
               rect.rangeLow = r.rangeLow;
               rect.rangeHigh = r.rangeHigh;
               ArrayResize(rangeRects, ArraySize(rangeRects)+1);
               rangeRects[ArraySize(rangeRects)-1] = rect;
            }
         }
      }

      if (ArraySize(rangeRects) > 0) {
         rangeRects[ArraySize(rangeRects)-1].endTime = Time[i];
      }
      
 
      i--;
   }
   
   for (int i = 0; i < ArraySize(rangeRects); i++) {
      CreateRect("RangeRect_" + (string)rangeRects[i].startTime + (string)i, rangeRects[i].startTime, rangeRects[i].rangeLow, rangeRects[i].endTime, rangeRects[i].rangeHigh, 0, 0, clrSalmon);
      ObjectSet("RangeRect_" + (string)rangeRects[i].startTime + (string)i, OBJPROP_SELECTABLE, false);
   }
}

class SR2Level {
public:
   FractalPoint* points[];
};
SR2Level allLevels[];

void SR2_levels(FractalPoint* &points[], SR2Level &levelsOut[], LookbackMode comparator) {
   FractalPoint* includedPoints[];

   for (int i = 0; i < ArraySize(points); i++) {
      FractalPoint* point1 = points[i];
      int numClosesOutsideRange = 0;

      SR2Level level;
      ArrayResize(level.points, 1);
      level.points[0] = point1;
      
      for (int j = i + 1; j < ArraySize(points); j++) {
         FractalPoint* point2 = points[j];
         bool found = false;
         
         for (int k = 0; k < ArraySize(includedPoints); k++) {
            if (includedPoints[k] == point2) {
               found = true;
               break;
            }
         }
         
         if (found) {
            break;
         }
         
         if (FractalPoint::InRange(point1, point2)) {
            numClosesOutsideRange = 0;
            ArrayResize(level.points, ArraySize(level.points)+1);
            level.points[ArraySize(level.points)-1] = point2;
         } else {
            if (maxClosesOutsideRange > 0) {
               int k = point2.index;

               if (j + 1 < ArraySize(points)) {
                  while (k > 0 && k > points[j + 1].index) {
                     if (comparator == LOOKBACK_GT) {
                        if (Close[k] > point1.val) {
                           numClosesOutsideRange++;
                        }
                     } else if (comparator == LOOKBACK_LT) {
                        if (Close[k] < point1.val) {
                           numClosesOutsideRange++;
                        }
                     }
                     k--;
                  }
               } else {
                  break;
               }

               if (numClosesOutsideRange >= maxClosesOutsideRange) break;
            }
         }
      }
      
      if (ArraySize(level.points) >= minRequiredPointsInRange) {
         for (int j = 0; j < ArraySize(level.points); j++) {
            ArrayResize(includedPoints, ArraySize(includedPoints)+1);
            includedPoints[ArraySize(includedPoints)-1] = level.points[j];
         }
         
         ArrayResize(levelsOut, ArraySize(levelsOut)+1);
         levelsOut[ArraySize(levelsOut)-1] = level;
      }
   }
}

void SR2(FractalPoint* &highs[], FractalPoint* &lows[]) {
   SR2Level levels_highs[];
   SR2Level levels_lows[];
   
   SR2_levels(highs, levels_highs, LOOKBACK_GT);
   SR2_levels(lows, levels_lows, LOOKBACK_LT);
   
   ArrayResize(allLevels, ArraySize(levels_highs)+ArraySize(levels_lows));

   for (int i = 0; i < ArraySize(levels_highs); i++) {
      allLevels[i] = levels_highs[i];
   }

   for (int i = 0; i < ArraySize(levels_lows); i++) {
      allLevels[ArraySize(levels_highs)+i] = levels_lows[i];
   }
   
   for (int i = 0; i < ArraySize(allLevels); i++) {
      if (ArraySize(allLevels[i].points) == 0) continue;

      double minVal = allLevels[i].points[0].val;
      double maxVal = allLevels[i].points[0].val;
      
      for (int j = 0; j < ArraySize(allLevels[i].points); j++) {
         minVal = MathMin(minVal, allLevels[i].points[j].val);
         maxVal = MathMax(maxVal, allLevels[i].points[j].val);
      }
      
      CreateRect("SR2_" + (string)i, allLevels[i].points[0].time, minVal, allLevels[i].points[ArraySize(allLevels[i].points)-1].time, maxVal, 0, 0, clrViolet, STYLE_DASH, 2);
      ObjectSet("SR2_" + (string)i, OBJPROP_SELECTABLE, false);
      
      /*ObjectCreate("SR2_" + (string)i,OBJ_TREND,0,allLevels[i].points[0].time, allLevels[i].points[0].val, allLevels[i].points[ArraySize(allLevels[i].points)-1].time, allLevels[i].points[0].val); 
      ObjectSet("SR2_" + (string)i,OBJPROP_COLOR, clrRed);
      ObjectSet("SR2_" + (string)i,OBJPROP_STYLE,STYLE_SOLID);
      ObjectSet("SR2_" + (string)i, OBJPROP_RAY, false);
      ObjectSet("SR2_" + (string)i,OBJPROP_WIDTH,1);*/
   }
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
                const int &spread[]) {
 
   int counted_bars = IndicatorCounted();
   int i = Bars - counted_bars - 1;
   //i = MathMin(i, 1000);
 
   while (i >= 0) {
      double upfrac_val=iFractals(NULL,0,MODE_UPPER,i);
      double lofrac_val=iFractals(NULL,0,MODE_LOWER,i);
      
      double fracVal = 0.0;
      
      FractalPoint* pt = NULL;
      
      if (upfrac_val > 0) {
         pt = new FractalPoint;
         pt.index = i;
         pt.time = Time[i];
         pt.val = Low[i];
         pt.dir = PointDirection::POINT_DIR_UP;
      } else if (lofrac_val > 0) {
         pt = new FractalPoint;
         pt.index = i;
         pt.time = Time[i];
         pt.val = High[i];
         pt.dir = PointDirection::POINT_DIR_DOWN;
      }
 
      if (pt != NULL) {
         pt.atr = iATR(NULL, 0, 14, i);
         ArrayResize(pts, ArraySize(pts)+1);
         pts[ArraySize(pts)-1] = pt;
      }
      
      i--;
   }

   FractalPoint* highs[];
   FractalPoint* lows[];
   ClassifySwingTypes(pts, highs, lows);
   // @TODO mark HH/LH etc on swing points to get lost/gained local highs and lows, and use S/R for entry
   
   if (SR2_enabled) {
      SR2(highs, lows);
   }
 
   if (SR1_enabled) {

      PointCluster* clusters[];
        
      for (int i = 0; i < ArraySize(pts); i++) {
         FractalPoint* inRange[];
         PointCluster* pc = new PointCluster;
         pc.lowerBound = pts[i].val;
         pc.upperBound = pts[i].val;
         
         for (int j = i + 1; j < ArraySize(pts); j++) {
            if (FractalPoint::InRange(pts[i], pts[j])) {
               ArrayResize(inRange, ArraySize(inRange)+1);
               inRange[ArraySize(inRange)-1] = pts[j];
               
               pc.lowerBound = MathMin(pc.lowerBound, pts[j].val);
               pc.upperBound = MathMax(pc.upperBound, pts[j].val);
            }
         }
         
         if (ArraySize(inRange) > 0) {
            pc.avg = pts[i].val;
            
            for (int j = 0; j < ArraySize(inRange); j++) {
               pc.avg += inRange[j].val;
            }
            
            pc.avg /= ArraySize(inRange) + 1;
            
            ArrayResize(clusters, ArraySize(clusters)+1);
            clusters[ArraySize(clusters)-1] = pc;
         }
      }
   
      double clusters_avg[];
      ArrayResize(clusters_avg, ArraySize(clusters));
      for (int i = 0; i < ArraySize(clusters); i++) {
         clusters_avg[i] = clusters[i].avg;
      }
      
      double jenks_breaks[];
      Jenks jenks;
      jenks.run(clusters_avg, SR1_resolution - 1, jenks_breaks);
      
      
      Range* ranges[];
      ArrayResize(ranges, ArraySize(jenks_breaks) - 1);
    
      for (int i = 0; i < ArraySize(jenks_breaks) - 1; i++) {
         ranges[i] = new Range;
         ranges[i].rangeLow = jenks_breaks[i];
         ranges[i].rangeHigh = jenks_breaks[i + 1];
         ranges[i].rangeMid = (ranges[i].rangeLow + ranges[i].rangeHigh) / 2;
      }
      
      
      for (int i = 0; i < ArraySize(ranges); i++) {
         //debuglog("jenks_breaks[" + (string)i + "] = " + (string)jenks_breaks[i]);
         ObjectMove(0, "SR_" + (string)i, 0, Time[0], ranges[i].rangeLow);
         // dont draw range high, it'll be range low of next
         
         // midline
         ObjectMove(0, "SR_" + (string)i + "_ML", 0, Time[0], ranges[i].rangeMid);
      }
      
      if (ENABLE_REJECTION_TEST) {
         RejectionTest(ranges);
         
         for (int i = 0; i < ArraySize(rejections); i++) {
            int arrow_type = rejections[i].type == REJECTION_BULL ? OBJ_ARROW_THUMB_UP : OBJ_ARROW_THUMB_DOWN;
            ObjectCreate(0, "RejectionArrow_" + (string)rejections[i].x, arrow_type, 0, rejections[i].x, rejections[i].y);
         }
      
      }
      
      
      //DetermineMovingRanges(ranges);
      
      
      for (int i = 0; i < ArraySize(ranges); i++) {
         delete ranges[i];
      }
    
      for (int i = 0; i < ArraySize(clusters); i++) {
         delete clusters[i];
      }
   }
   //}
   
   return rates_total;
}
