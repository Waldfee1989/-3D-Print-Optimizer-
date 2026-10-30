#include "geometry_core.h"
#include <jni.h>
#include <exception>
extern "C" JNIEXPORT jobjectArray JNICALL
Java___JNI_PACKAGE___OptimizerGeometry_nativeCut(JNIEnv* env,jobject,jfloatArray input,jdouble scale,jint axis,jdouble fraction,
                                                jboolean pins,jdouble diameter,jdouble length,jdouble clearance) {
  jfloat* values=nullptr;
  try {
    values=env->GetFloatArrayElements(input,nullptr);
    if (!values) return nullptr;
    const auto result=CutModel(values,env->GetArrayLength(input),scale,axis,fraction,pins,diameter,length,clearance);
    env->ReleaseFloatArrayElements(input,values,JNI_ABORT);values=nullptr;
    const auto klass=env->FindClass("[F");
    auto array=env->NewObjectArray(2,klass,nullptr);
    if (!array) return nullptr;
    const std::vector<float>* pieces[]={&result.first,&result.second};
    for (int i=0;i<2;i++) {
      auto piece=env->NewFloatArray(pieces[i]->size());
      if (!piece) return nullptr;
      env->SetFloatArrayRegion(piece,0,pieces[i]->size(),pieces[i]->data());
      env->SetObjectArrayElement(array,i,piece);env->DeleteLocalRef(piece);
    }
    return array;
  } catch (const std::exception& e) {
    if (values) env->ReleaseFloatArrayElements(input,values,JNI_ABORT);
    env->ThrowNew(env->FindClass("java/lang/IllegalArgumentException"),e.what());return nullptr;
  }
}
