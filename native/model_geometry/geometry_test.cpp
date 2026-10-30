#include "geometry_core.h"
#include <manifold/manifold.h>
#include <manifold/mesh.h>
#include <cmath>
#include <iostream>
#include <stdexcept>
std::vector<float> Flat(const manifold::Manifold& m) {
  const auto mesh=m.GetMeshGL();std::vector<float> v;
  for(auto i:mesh.triVerts)for(int k=0;k<3;k++)v.push_back(mesh.vertProperties[i*mesh.numProp+k]);return v;
}
manifold::Manifold Rebuild(const std::vector<float>& v) {
  manifold::MeshGL mesh;mesh.vertProperties=v;
  for(std::size_t i=0;i<v.size()/3;i++)mesh.triVerts.push_back(i);
  mesh.Merge();const manifold::Manifold m(mesh);
  if(m.Status()!=manifold::Manifold::Error::NoError || m.Volume()<=0)throw std::runtime_error("Output not manifold");
  return m;
}
void Check(const std::vector<float>& v) { Rebuild(v); }
int main() {
  const auto v=Flat(manifold::Manifold::Cube({40,40,40},true));
  for(int axis=0;axis<3;axis++) {
    const auto result=CutModel(v.data(),v.size(),1,axis,.5,true,4,5,.2);
    Check(result.first);Check(result.second);
    if(result.first.size()<=18 || result.second.size()<=18)throw std::runtime_error("Cut empty");
  }
  const auto noPins=CutModel(v.data(),v.size(),1,2,.5,false,4,5,.2);Check(noPins.first);Check(noPins.second);
  bool rejected=false;try{CutModel(v.data(),v.size(),1,2,.5,true,30,30,.2);}catch(const std::exception&){rejected=true;}
  if(!rejected)throw std::runtime_error("Insufficient material was not rejected");
  for(int kind : {2,3})for(int axis=0;axis<3;axis++) {
    const double diameter=kind==2 ? 10 : 6,height=kind==2 ? 8 : 10;
    const auto result=CutModel(v.data(),v.size(),1,axis,.5,kind,diameter,height,.2,2);
    const auto lower=Rebuild(result.first),upper=Rebuild(result.second);
    if(lower.Decompose().size()!=1 || upper.Decompose().size()!=1)throw std::runtime_error("Disconnected connector");
    if(lower.Volume()<=32000 || upper.Volume()>=32000)throw std::runtime_error("Missing male or socket");
    const auto overlap=lower.Boolean(upper,manifold::OpType::Intersect);
    if(overlap.Volume()>.01)throw std::runtime_error("Assembled connection interferes");
    if(kind==2 && axis==2) {
      // A real helix must stay clear while the socket rotates and retreats
      // by the corresponding fraction of one pitch, not merely at rest.
      for(double angle : {90.,180.,270.}) {
        const auto unscrewed=upper.Rotate(0,0,angle).Translate({0,0,2*angle/360});
        if(lower.Boolean(unscrewed,manifold::OpType::Intersect).Volume()>.01)
          throw std::runtime_error("Helical thread motion interferes");
      }
      bool crest=false,root=false;
      for(std::size_t i=0;i<result.first.size();i+=3) {
        const double z=result.first[i+2],r=std::hypot(result.first[i],result.first[i+1]);
        if(z>1 && z<4){if(r>4.9 && r<5.1)crest=true;if(r>4.1 && r<4.3)root=true;}
      }
      if(!crest || !root)throw std::runtime_error("Thread is missing its helical relief");
    }
    if(kind==3 && axis==2) {
      int clips=0;
      for(double x:{-14.,14.})for(double y:{-14.,14.}) {
        const auto arm=manifold::Manifold::Cube({.2,.2,1}).Translate({x+1.9,y-.1,1});
        if(lower.Boolean(arm,manifold::OpType::Intersect).Volume()<.03)continue;
        clips++;
        const auto slot=manifold::Manifold::Cube({.4,1,3}).Translate({x-.2,y-.5,1});
        if(lower.Boolean(slot,manifold::OpType::Intersect).Volume()>.0001)
          throw std::runtime_error("Snap cantilever slot is filled");
        const auto hook=manifold::Manifold::Cylinder(.2,.02,.02,12).Translate({x+2.4,y+2.4,7});
        if(lower.Boolean(hook,manifold::OpType::Intersect).Volume()<.0002)
          throw std::runtime_error("Snap retaining lip is missing");
      }
      if(clips!=2)throw std::runtime_error("Expected two separate snap connectors");
    }
  }
  for(const auto spec : {std::vector<double>{2,6,8,2}, {2,10,4,2}, {3,6,5,2}}) {
    bool invalid=false;try{CutModel(v.data(),v.size(),1,2,.5,static_cast<int>(spec[0]),spec[1],spec[2],.2,spec[3]);}
    catch(const std::exception&){invalid=true;}
    if(!invalid)throw std::runtime_error("Unsafe connector parameters accepted");
  }
  std::cout << "Closed cuts, pin, helical screw motion, snap geometry and invalid-parameter rejection passed.\n";
}
