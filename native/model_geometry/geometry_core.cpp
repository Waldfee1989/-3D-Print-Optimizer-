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
// A truncated helical profile, sampled in angle and height. Both mating
// surfaces use the same pitch and phase; the socket adds radial/axial play.
Manifold ThreadForm(double radius,double height,double pitch,double clearance,bool socket) {
  const double root=radius-.4*pitch, start=-1.0;
  const double end=height+(socket ? .6 : 0.0);
  const int around=96, levels=static_cast<int>(std::ceil((end-start)/pitch*24));
  MeshGL64 mesh; mesh.numProp=3;
  constexpr double tau=6.2831853071795864769;
  for(int i=0;i<=levels;i++) {
    const double z=start+(end-start)*i/levels;
    for(int j=0;j<around;j++) {
      const double angle=tau*j/around;
      double phase=z/pitch-angle/tau;phase-=std::floor(phase);
      double distance=std::abs(phase-.5)*2;
      if(socket)distance=std::max(0.0,distance-2*clearance/pitch);
      const double ridge=std::clamp((.8-distance)/.6,0.0,1.0);
      const double lead=socket ? 1.0 : std::clamp((height-z)/pitch,0.0,1.0);
      double r=root+.4*pitch*ridge*lead+(socket ? clearance : 0);
      if(socket && z<.6)r=std::max(r,radius+clearance-(radius-root)*std::clamp(z/.6,0.0,1.0));
      mesh.vertProperties.insert(mesh.vertProperties.end(),{r*std::cos(angle),r*std::sin(angle),z});
    }
  }
  for(int i=0;i<levels;i++)for(int j=0;j<around;j++) {
    const unsigned a=i*around+j,b=i*around+(j+1)%around,c=(i+1)*around+j,d=(i+1)*around+(j+1)%around;
    for(auto index:{a,b,c,b,d,c})mesh.triVerts.push_back(index);
  }
  const unsigned bottom=mesh.vertProperties.size()/3;
  mesh.vertProperties.insert(mesh.vertProperties.end(),{0,0,start,0,0,end});
  for(int j=0;j<around;j++) {
    for(auto index:{bottom,static_cast<unsigned>((j+1)%around),static_cast<unsigned>(j)})mesh.triVerts.push_back(index);
    for(auto index:{bottom+1,static_cast<unsigned>(levels*around+j),static_cast<unsigned>(levels*around+(j+1)%around)})mesh.triVerts.push_back(index);
  }
  Manifold result(mesh);Valid(result);return result;
}
struct Joint {Manifold male,socket;};
Joint MakeJoint(int kind,double radius,double height,double clearance,double pitch) {
  if(kind==2)return {ThreadForm(radius,height,pitch,0,false),ThreadForm(radius,height,pitch,clearance,true)};
  if(kind==3) {
    const double lip=std::min(.55,radius*.14),slot=std::clamp(radius*.4,.8,1.6);
    // Split stud: two cantilevers, retaining shoulder, and a tapered lead-in.
    const double shoulder=height*.68, crest=height*.76;
    auto male=Manifold::Cylinder(height+1,radius,radius,64).Translate({0,0,-1});
    male=male.Boolean(Manifold::Cylinder(crest-shoulder,radius+lip,radius+lip,64).Translate({0,0,shoulder}),manifold::OpType::Add);
    male=male.Boolean(Manifold::Cylinder(height-crest,radius+lip,radius*.85,64).Translate({0,0,crest}),manifold::OpType::Add);
    const auto gap=Manifold::Cube({slot,2*(radius+lip+1),height+.7}).Translate({-slot/2,-radius-lip-1,-.5});
    male=male.Boolean(gap,manifold::OpType::Subtract);
    auto socket=CylinderAt(0,0,-.1,height+.7,radius+clearance);
    const auto groove=CylinderAt(0,0,shoulder-clearance,height-shoulder+2*clearance+.3,radius+lip+clearance);
    socket=socket.Boolean(groove,manifold::OpType::Add);
    return {male,socket};
  }
  return {Manifold::Cylinder(height+1,radius,radius*.95,48).Translate({0,0,-1}),CylinderAt(0,0,-.1,height+.6,radius+clearance)};
}
bool Contained(const Manifold& solid,const Manifold& probe) {
  const double full=probe.Volume();
  const auto overlap=solid.Boolean(probe,manifold::OpType::Intersect);
  return overlap.Status()==Manifold::Error::NoError && overlap.Volume()>full*.995;
}
}
CutOutput CutModel(const float* v,std::size_t length,double unitScale,int axis,double fraction,
                   int connection,double diameter,double pinLength,double clearance,double pitch) {
  if (!v || length==0 || length%9 || length/9>2100000 || !std::isfinite(unitScale) || unitScale<=0 ||
      connection<0 || connection>3 || axis<0 || axis>2 || !std::isfinite(fraction) || fraction<=.01 || fraction>=.99 ||
      !std::isfinite(diameter) || diameter<2 || diameter>30 || !std::isfinite(pinLength) || pinLength<2 || pinLength>30 ||
      !std::isfinite(clearance) || clearance<.05 || clearance>1)
    throw std::runtime_error("Ungueltige Schnitt- oder Verbinderwerte.");
  if (connection==2 && (!std::isfinite(pitch) || pitch<1 || pitch>4 || diameter<8 || diameter/2-.4*pitch<2 || pinLength<3*pitch))
    throw std::runtime_error("Gewinde: Durchmesser ab 8 mm, Steigung 1 bis 4 mm, Laenge mindestens drei Steigungen.");
  if (connection==3 && (diameter<4 || pinLength<6 || pinLength/diameter<1.2))
    throw std::runtime_error("Klickverschluss: Durchmesser ab 4 mm, Laenge ab 6 mm und mindestens 1,2 mal Durchmesser.");
  if(connection==2 && clearance>.4*pitch-.1)
    throw std::runtime_error("Gewindespiel ist zu gross fuer die gewaehlte Steigung.");
  if(connection==3 && clearance>std::min(.55,diameter*.07)-.05)
    throw std::runtime_error("Klickspiel ist groesser als die Haltekante. Spiel reduzieren.");
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
  if (connection!=0) {
    const auto loops=solid.Slice(cut);
    if (loops.empty()) throw std::runtime_error("Keine geeignete Schnittflaeche fuer Verbinder.");
    const double r=diameter/2,wall=1.2,extra=connection==3 ? std::min(.55,r*.14) : 0;
    const double envelope=r+clearance+extra+wall;
    std::vector<vec2> candidates;
    for (int iy=1;iy<20;iy++) for (int ix=1;ix<20;ix++) {
      vec2 p={box.min.x+(box.max.x-box.min.x)*ix/20,box.min.y+(box.max.y-box.min.y)*iy/20};
      if (Inside(p,loops) && BoundaryDistance(p,loops)>envelope) candidates.push_back(p);
    }
    auto fits=[&](vec2 p) {
      return Contained(solid,CylinderAt(p.x,p.y,cut-1.3,1.1,envelope)) &&
        Contained(solid,CylinderAt(p.x,p.y,cut+.05,pinLength+wall+.6,envelope));
    };
    std::vector<vec2> centers;
    if(connection==2) {
      const auto center=box.Center();
      std::sort(candidates.begin(),candidates.end(),[&](vec2 a,vec2 b) {
        return std::hypot(a.x-center.x,a.y-center.y)<std::hypot(b.x-center.x,b.y-center.y);
      });
      for(std::size_t i=0;i<std::min<std::size_t>(candidates.size(),48);i++)if(fits(candidates[i])) {centers.push_back(candidates[i]);break;}
    } else {
      struct Pair {double score;vec2 a,b;}; std::vector<Pair> pairs;
      for (std::size_t i=0;i<candidates.size();i++) for (std::size_t j=i+1;j<candidates.size();j++) {
        const double distance=std::hypot(candidates[i].x-candidates[j].x,candidates[i].y-candidates[j].y);
        if (distance>2*envelope+1) pairs.push_back({distance,candidates[i],candidates[j]});
      }
      std::sort(pairs.begin(),pairs.end(),[](const Pair& a,const Pair& b){return a.score>b.score;});
      for (std::size_t i=0;i<std::min<std::size_t>(pairs.size(),24);i++)if(fits(pairs[i].a)&&fits(pairs[i].b)) {
        centers={pairs[i].a,pairs[i].b};break;
      }
    }
    if (centers.empty()) throw std::runtime_error("Zu wenig massives Material fuer die Verbindung. Anderen Schnitt oder kleinere Verbinder waehlen.");
    const auto joint=MakeJoint(connection,r,pinLength,clearance,pitch);
    Valid(joint.male);Valid(joint.socket);
    for (auto p : centers) {
      lower=lower.Boolean(joint.male.Translate({p.x,p.y,cut}),manifold::OpType::Add);
      upper=upper.Boolean(joint.socket.Translate({p.x,p.y,cut}),manifold::OpType::Subtract);
      Valid(lower);Valid(upper);
    }
  }
  if (axis==0) {lower=lower.Rotate(0,90,0);upper=upper.Rotate(0,90,0);}
  if (axis==1) {lower=lower.Rotate(-90,0,0);upper=upper.Rotate(-90,0,0);}
  return {Flatten(lower),Flatten(upper)};
}
