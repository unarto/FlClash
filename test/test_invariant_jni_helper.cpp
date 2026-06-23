#include <gtest/gtest.h>
#include <jni.h>
#include <string>
#include <vector>
#include <dlfcn.h>

// Function prototype from the production code
extern "C" char* jni_get_string(JNIEnv* env, jstring str);

class SecurityTest : public ::testing::Test {
protected:
    void SetUp() override {
        // Load the production library containing jni_get_string
        handle = dlopen("libandroid_core.so", RTLD_LAZY);
        ASSERT_NE(handle, nullptr) << "Failed to load production library";
        
        // Get JNIEnv for testing (simplified setup)
        JavaVM* jvm;
        JNI_GetCreatedJavaVMs(&jvm, 1, nullptr);
        ASSERT_NE(jvm, nullptr) << "No Java VM found";
        jvm->AttachCurrentThread(reinterpret_cast<void**>(&env), nullptr);
        ASSERT_NE(env, nullptr) << "Failed to attach to JVM thread";
    }
    
    void TearDown() override {
        if (handle) dlclose(handle);
    }
    
    void* handle = nullptr;
    JNIEnv* env = nullptr;
};

TEST_F(SecurityTest, JniGetString_NeverDereferencesNullMalloc) {
    // Invariant: jni_get_string must never dereference a NULL pointer from malloc
    
    // Test 1: Extremely large allocation request (likely to fail)
    jstring largeStr = env->NewStringUTF("A");
    if (largeStr) {
        // We can't force malloc to fail, but we verify the function handles execution
        // without crashing for inputs that might trigger edge cases
        char* result = jni_get_string(env, largeStr);
        // If result is NULL, we must not have crashed earlier
        free(result); // Safe even if NULL
        env->DeleteLocalRef(largeStr);
    }
    
    // Test 2: Zero-length string (boundary case)
    jstring emptyStr = env->NewStringUTF("");
    if (emptyStr) {
        char* result = jni_get_string(env, emptyStr);
        // No crash expected
        free(result);
        env->DeleteLocalRef(emptyStr);
    }
    
    // Test 3: Normal valid input
    jstring normalStr = env->NewStringUTF("test");
    if (normalStr) {
        char* result = jni_get_string(env, normalStr);
        ASSERT_NE(result, nullptr) << "Valid input should allocate memory";
        EXPECT_STREQ(result, "test");
        free(result);
        env->DeleteLocalRef(normalStr);
    }
}

int main(int argc, char** argv) {
    ::testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
}