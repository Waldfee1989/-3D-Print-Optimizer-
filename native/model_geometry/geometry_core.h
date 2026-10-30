#pragma once
#include <vector>
#include <cstddef>
struct CutOutput { std::vector<float> first,second; };
CutOutput CutModel(const float* vertices,std::size_t length,double unitScale,int axis,double fraction,
                   bool pins,double diameter,double pinLength,double clearance);
