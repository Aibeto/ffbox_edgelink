plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "top.raincrat.aibeto.ffboxedgelink"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "top.raincrat.aibeto.ffboxedgelink"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 内置 FFBox 服务：仅 arm64（nodejs-mobile 运行时体积与目标架构控制）。
        // 注意：Flutter 插件 apply 时会 clear 并写入全部平台 ABI（armeabi-v7a/arm64-v8a/x86_64），
        // 此处必须 clear 后重新限定，否则 armeabi-v7a 缺少 libnode.so 会导致 CMake 构建失败。
        ndk {
            abiFilters.clear()
            abiFilters.addAll(listOf("arm64-v8a"))
        }

        // libnode.so 依赖 libc++_shared.so（NDK C++ 运行时），
        // 设置 ANDROID_STL=c++_shared 使 Gradle 自动打包对应的 so 文件。
        externalNativeBuild {
            cmake {
                arguments += "-DANDROID_STL=c++_shared"
            }
        }
    }

    externalNativeBuild {
        // nodejs-mobile JNI 桥（cpp/nodejni.cpp）
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    // 内置 ffmpeg/ffprobe 以 lib*.so 打入 jniLibs，安装后需解压到磁盘
    // （nativeLibraryDir）才能被 exec。Android 10+（targetSdk≥29）的
    // SELinux W^X 限制禁止 exec 应用数据目录文件，nativeLibraryDir 是
    // App 唯一可执行自带二进制的位置，故必须开启 legacy packaging。
    packagingOptions {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 实时活动前台服务：协程轮询 + NotificationCompat（API < 36 回退）
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
}
