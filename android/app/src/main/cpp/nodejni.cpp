#include <jni.h>
#include <string>
#include <cstdlib>
#include <vector>

#include "node.h"

// JNI 桥：将 Java 参数数组转换为 argc/argv 后启动 nodejs-mobile 引擎。
// node::Start 阻塞直至 Node 线程退出（引擎设计为常驻，正常情况下不返回）。
extern "C" JNIEXPORT jint JNICALL
Java_top_raincrat_aibeto_ffboxedgelink_localnode_LocalNodeService_startNodeWithArguments(
        JNIEnv *env, jobject /*thiz*/, jobjectArray arguments) {
    int argc = env->GetArrayLength(arguments);
    std::vector<char *> argv;
    argv.reserve(argc);
    for (int i = 0; i < argc; i++) {
        auto *arg = (jstring) env->GetObjectArrayElement(arguments, i);
        const char *chars = env->GetStringUTFChars(arg, nullptr);
        argv.push_back(strdup(chars));
        env->ReleaseStringUTFChars(arg, chars);
        env->DeleteLocalRef(arg);
    }
    return node::Start(argc, argv.data());
}
