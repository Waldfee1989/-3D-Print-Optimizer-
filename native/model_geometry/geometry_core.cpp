#include "geometry_core.h"
#include <manifold/manifold.h>
#include <manifold/mesh.h>
#include <algorithm>
#include <cmath>
#include <limits>
#include <stdexcept>
using manifold::Manifold;
using manifold::MeshGL64;
using manifold::vec2;
using manifold::vec3;
namespace {
void Valid(const Manifold& m) {
  if (m.Status() != Manifold::Error::NoError || m.IsEmpty())
    throw std::runtime_error("Geometrie ist nicht geschlossen oder der Schnitt ist ungueltig.");
}
std::vector<float> Flatten(const Manifold& m) {
  Valid(m);
  const auto mesh = m.GetMeshGL64();
  if (mesh.NumTri() > 2500000) throw std::runtime_error("Geschnittenes Modell ist zu gross.");
  std::vector<float> out; out.reserve(mesh.triVerts.size()*3);
  for (auto v : mesh.triVerts) for (int k=0;k<3;k++) out.push_back(static_cast<float>(mesh.vertProperties[v*mesh.numProp+k]));
  return out;
}
double BoundaryDistance(vec2 p,const manifold::Polygons& loops) {
  double distance = std::numeric_limits<double>::infinity();
  for (const auto& loop : loops) for (std::size_t i=0;i<loop.size();i++) {
    const vec2 a=loop[i],b=loop[(i+1)%loop.size()];
    const double dx=b.x-a.x,dy=b.y-a.y,len=dx*dx+dy*dy;
    const double t=len>0 ? std::clamp(((p.x-a.x)*dx+(p.y-a.y)*dy)/len,0.0,1.0) : 0;
    distance=std::min(distance,std::hypot(p.x-a.x-t*dx,p.y-a.y-t*dy));
  }
  return distance;
}
bool Inside(vec2 p,const manifold::Polygons& loops) {
  bool inside=false;
  for (const auto& loop : loops) for (std::size_t i=0,j=loop.size()-1;i<loop.size();j=i++) {
    const auto a=loop[i],b=loop[j];
    if (((a.y>p.y)!=(b.y>p.y)) && p.x<(b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x) inside=!inside;
  }
  return inside;
}
Manifold CylinderAt(double x,double y,double z,double height,double radius) {
  return Manifold::Cylinder(height,radius,radius,48).Translate({x,y,z});
}
bool Contained(const Manifold& solid,const Manifold& probe) {
  const double full=probe.Volume();
  const auto overlap=solid.Boolean(probe,manifold::OpType::Intersect);
  return overlap.Status()==Manifold::Error::NoError && overlap.Volume()>full*.995;
}
}
CutOutput CutModel(const float* v,std::size_t length,double unitScale,int axis,double fraction,
                   bool pins,double diameter,double pinLength,double clearance) {
  if (!v || length==0 || length%9 || length/9>2100000 || !std::isfinite(unitScale) || unitScale<=0 ||
      axis<0 || axis>2 || !std::isfinite(fraction) || fraction<=.01 || fraction>=.99 ||
      !std::isfinite(diameter) || diameter<2 || diameter>30 || !std::isfinite(pinLength) || pinLength<2 || pinLength>30 ||
      !std::isfinite(clearance) || clearance<.05 || clearance>1)
    throw std::runtime_error("Ungueltige Schnitt- oder Verbinderwerte.");
  MeshGL64 mesh; mesh.numProp=3; mesh.vertProperties.reserve(length); mesh.triVerts.reserve(length/3);
  double volume=0;
  for (std::size_t i=0;i<length;i+=9) {
    double p[9];
    for (int k=0;k<9;k++) { p[k]=v[i+k]*unitScale; if (!std::isfinite(p[k]) || std::abs(p[k])>1000000) throw std::runtime_error("Modellkoordinaten ausserhalb des Bereichs."); }
    volume+=p[0]*(p[4]*p[8]-p[5]*p[7])+p[1]*(p[5]*p[6]-p[3]*p[8])+p[2]*(p[3]*p[7]-p[4]*p[6]);
  }
  for (std::size_t i=0;i<length;i+=9) for (int corner=0;corner<3;corner++) {
    const int source=volume<0 ? (corner==1 ? 2 : corner==2 ? 1 : 0) : corner;
    for (int k=0;k<3;k++) mesh.vertProperties.push_back(v[i+source*3+k]*unitScale);
    mesh.triVerts.push_back(mesh.triVerts.size());
  }
  mesh.Merge();
  Manifold solid(mesh); Valid(solid);
  if (axis==0) solid=solid.Rotate(0,-90,0);
  if (axis==1) solid=solid.Rotate(90,0,0);
  const auto box=solid.BoundingBox();
  const double cut=box.min.z+(box.max.z-box.min.z)*fraction;
  const auto split=solid.SplitByPlane({0,0,1},cut);
  Manifold lower=split.first,upper=split.second;
  if (lower.BoundingBox().Center().z>upper.BoundingBox().Center().z) std::swap(lower,upper);
  Valid(lower); Valid(upper);
  if (pins) {
    const auto loops=solid.Slice(cut);
    if (loops.empty()) throw std::runtime_error("Keine geeignete Schnittflaeche fuer Verbinder.");
    const double r=diameter/2,wall=1.0;
    std::vector<vec2> candidates;
    for (int iy=1;iy<19;iy++) for (int ix=1;ix<19;ix++) {
      vec2 p={box.min.x+(box.max.x-box.min.x)*ix/19,box.min.y+(box.max.y-box.min.y)*iy/19};
      if (Inside(p,loops) && BoundaryDistance(p,loops)>r+clearance+wall) candidates.push_back(p);
    }
    struct Pair {double score;vec2 a,b;}; std::vector<Pair> pairs;
    for (std::size_t i=0;i<candidates.size();i++) for (std::size_t j=i+1;j<candidates.size();j++) {
      const double distance=std::hypot(candidates[i].x-candidates[j].x,candidates[i].y-candidates[j].y);
      if (distance>diameter+3) pairs.push_back({distance,candidates[i],candidates[j]});
    }
    std::sort(pairs.begin(),pairs.end(),[](const Pair& a,const Pair& b){return a.score>b.score;});
    bool found=false; vec2 centers[2];
    for (std::size_t i=0;i<std::min<std::size_t>(pairs.size(),12);i++) {
      const auto& pair=pairs[i];
      bool fits=true;
      for (auto p : {pair.a,pair.b}) {
        // Check material under the pin and around/deeper than the socket.
        if (!Contained(solid,CylinderAt(p.x,p.y,cut-1.2,1.0,r+wall)) ||
            !Contained(solid,CylinderAt(p.x,p.y,cut+.1,pinLength+1.0,r+clearance+wall))) { fits=false; break; }
      }
      if (fits) {centers[0]=pair.a;centers[1]=pair.b;found=true;break;}
    }
    if (!found) throw std::runtime_error("Zu wenig massives Material fuer zwei Zapfen. Anderen Schnitt oder kleinere Verbinder waehlen.");
    for (auto p : centers) {
      const auto pin=Manifold::Cylinder(pinLength+1, r,r*.95,48).Translate({p.x,p.y,cut-1});
      const auto socket=CylinderAt(p.x,p.y,cut-.1,pinLength+.6,r+clearance);
      lower=lower.Boolean(pin,manifold::OpType::Add);
      upper=upper.Boolean(socket,manifold::OpType::Subtract);
      Valid(lower);Valid(upper);
    }
  }
  if (axis==0) {lower=lower.Rotate(0,90,0);upper=upper.Rotate(0,90,0);}
  if (axis==1) {lower=lower.Rotate(-90,0,0);upper=upper.Rotate(-90,0,0);}
  return {Flatten(lower),Flatten(upper)};
}
