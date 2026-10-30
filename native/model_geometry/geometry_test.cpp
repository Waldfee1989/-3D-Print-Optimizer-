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
void Check(const std::vector<float>& v) {
  manifold::MeshGL mesh;mesh.vertProperties=v;
  for(std::size_t i=0;i<v.size()/3;i++)mesh.triVerts.push_back(i);
  mesh.Merge();const manifold::Manifold m(mesh);
  if(m.Status()!=manifold::Manifold::Error::NoError || m.Volume()<=0)throw std::runtime_error("Output not manifold");
}
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
  std::cout << "Closed cuts, pin/socket unions and insufficient-material rejection passed.\n";
}
