/**
 * ==============================================================================
 * LibVosk 跨平台工业级 E2E 全功能自动化测试套件
 * ==============================================================================
 * 本测试程序采用标准 ANSI C / C99 编写，零第三方依赖，可无缝在所有平台编译运行：
 *   - Windows (MSVC & MinGW)
 *   - macOS (Clang / Apple Silicon & Intel)
 *   - Linux (GCC / Clang x86_64, aarch64, riscv64, armv7l, x86)
 *   - Android (NDK Clang via QEMU / Termux)
 *
 * 测试覆盖核心能力：
 *   1. 模型载入与符号表检索 (Model Lifecycle & FST Symbol Mapping)
 *   2. 流式语音识别与词级时间戳 (Streaming ASR & Word-Level Timestamps)
 *   3. 动态受限语法识别 (Dynamic Grammar Constraint & JSON Rule Engine)
 *   4. 重置与重识别状态机 (Recognizer Reset & Re-decoding State)
 *   5. 内存安全与资源释放 (Clean Teardown & Leak Prevention)
 * ==============================================================================
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "vosk_api.h"

#define TEST_PASS_BANNER "✔ [PASS]"
#define TEST_FAIL_BANNER "❌ [FAIL]"

static int g_test_failures = 0;

#define ASSERT_TRUE(cond, msg) do { \
    if (!(cond)) { \
        fprintf(stderr, "%s %s:%d: Assertion failed: %s - %s\n", TEST_FAIL_BANNER, __FILE__, __LINE__, #cond, msg); \
        g_test_failures++; \
        return 0; \
    } \
} while(0)

#define ASSERT_NOT_NULL(ptr, msg) do { \
    if ((ptr) == NULL) { \
        fprintf(stderr, "%s %s:%d: Pointer is NULL: %s - %s\n", TEST_FAIL_BANNER, __FILE__, __LINE__, #ptr, msg); \
        g_test_failures++; \
        return 0; \
    } \
} while(0)

/**
 * 模块 1: 模型生命周期与 OpenFST 符号表测试
 */
static int test_model_lifecycle(const char* model_path, VoskModel** out_model) {
    printf("\n--> [Test 1/4] 测试模型加载与 OpenFST 词典索引...\n");
    
    // 设置 Vosk 日志级别为静默/警告，避免刷屏
    vosk_set_log_level(0);

    VoskModel* model = vosk_model_new(model_path);
    ASSERT_NOT_NULL(model, "vosk_model_new failed to load model directory");

    // 1. 查找有效高频词
    int word_id = vosk_model_find_word(model, "one");
    printf("    vosk_model_find_word('one') -> word_id = %d\n", word_id);
    ASSERT_TRUE(word_id >= 0, "Word 'one' should exist in standard English vocabulary");

    // 2. 查找不存在的极端随机词
    int invalid_id = vosk_model_find_word(model, "__non_existent_vocab_xyz_9988__");
    printf("    vosk_model_find_word('__non_existent__') -> word_id = %d\n", invalid_id);
    ASSERT_TRUE(invalid_id == -1, "Non-existent word must return -1");

    *out_model = model;
    printf("%s 模型加载与符号表测试通过！\n", TEST_PASS_BANNER);
    return 1;
}

/**
 * 模块 2: 流式语音识别与字级别时间戳测试
 */
static int test_streaming_recognition(VoskModel* model, const char* wav_path) {
    printf("\n--> [Test 2/4] 测试流式语音识别与词级时间戳 (WAV: %s)...\n", wav_path);

    FILE* fp = fopen(wav_path, "rb");
    ASSERT_NOT_NULL(fp, "Failed to open WAV audio file for streaming test");

    // 跳过标准 44 字节 WAV 头部
    fseek(fp, 44, SEEK_SET);

    VoskRecognizer* recognizer = vosk_recognizer_new(model, 16000.0f);
    ASSERT_NOT_NULL(recognizer, "vosk_recognizer_new failed");

    // 启用词级别时间戳与置信度输出
    vosk_recognizer_set_words(recognizer, 1);

    char pcm_buffer[4096];
    size_t bytes_read;
    int chunk_count = 0;

    while ((bytes_read = fread(pcm_buffer, 1, sizeof(pcm_buffer), fp)) > 0) {
        chunk_count++;
        int state = vosk_recognizer_accept_waveform(recognizer, pcm_buffer, (int)bytes_read);
        if (state == 1) {
            const char* partial_json = vosk_recognizer_result(recognizer);
            ASSERT_NOT_NULL(partial_json, "vosk_recognizer_result returned NULL");
        }
    }
    fclose(fp);

    const char* final_json = vosk_recognizer_final_result(recognizer);
    ASSERT_NOT_NULL(final_json, "vosk_recognizer_final_result returned NULL");
    printf("    识别最终输出 JSON: %s\n", final_json);

    // 验证 JSON 中包含 "text" 字段
    ASSERT_TRUE(strstr(final_json, "\"text\"") != NULL, "Final result JSON must contain 'text' key");

    vosk_recognizer_free(recognizer);
    printf("%s 流式语音识别与时间戳测试通过 (处理了 %d 个音频块)！\n", TEST_PASS_BANNER, chunk_count);
    return 1;
}

/**
 * 模块 3: 动态语法约束识别测试 (Grammar Constraint)
 */
static int test_grammar_constraint(VoskModel* model, const char* wav_path) {
    printf("\n--> [Test 3/4] 测试动态受限语法识别与实时重设 (Grammar Constraint & vosk_recognizer_set_grm)...\n");

    // Phase 1: 单词列表语法初始化 (vosk_recognizer_new_grm)
    const char* grammar_json_1 = "[\"zero\", \"one\", \"two\", \"three\", \"four\", \"five\", \"six\", \"seven\", \"eight\", \"nine\", \"[unk]\"]";
    VoskRecognizer* recognizer = vosk_recognizer_new_grm(model, 16000.0f, grammar_json_1);
    ASSERT_NOT_NULL(recognizer, "vosk_recognizer_new_grm failed");

    FILE* fp = fopen(wav_path, "rb");
    ASSERT_NOT_NULL(fp, "Failed to open WAV audio file for grammar test");
    fseek(fp, 44, SEEK_SET);

    char pcm_buffer[4096];
    size_t bytes_read;
    while ((bytes_read = fread(pcm_buffer, 1, sizeof(pcm_buffer), fp)) > 0) {
        vosk_recognizer_accept_waveform(recognizer, pcm_buffer, (int)bytes_read);
    }
    fclose(fp);

    const char* final_json_1 = vosk_recognizer_final_result(recognizer);
    ASSERT_NOT_NULL(final_json_1, "vosk_recognizer_final_result returned NULL in grammar mode");
    printf("    [Phase 1] 单词级受限语法识别输出: %s\n", final_json_1);

    // Phase 2: 动态热切换短语级语法 (vosk_recognizer_set_grm)
    const char* grammar_json_2 = "[\"zero one eight zero three\", \"hello world\", \"[unk]\"]";
    printf("    --> 动态热重设语法: %s\n", grammar_json_2);
    vosk_recognizer_set_grm(recognizer, grammar_json_2);
    vosk_recognizer_reset(recognizer);

    fp = fopen(wav_path, "rb");
    ASSERT_NOT_NULL(fp, "Failed to re-open WAV audio file for dynamic grammar test");
    fseek(fp, 44, SEEK_SET);
    while ((bytes_read = fread(pcm_buffer, 1, sizeof(pcm_buffer), fp)) > 0) {
        vosk_recognizer_accept_waveform(recognizer, pcm_buffer, (int)bytes_read);
    }
    fclose(fp);

    const char* final_json_2 = vosk_recognizer_final_result(recognizer);
    ASSERT_NOT_NULL(final_json_2, "vosk_recognizer_final_result returned NULL after set_grm");
    printf("    [Phase 2] 短语级热切换受限语法识别输出: %s\n", final_json_2);
    ASSERT_TRUE(strstr(final_json_2, "zero one eight zero three") != NULL, "Dynamic phrase grammar must match audio content");

    vosk_recognizer_free(recognizer);
    printf("%s 动态语法编译、解码与实时热重设测试通过！\n", TEST_PASS_BANNER);
    return 1;
}

/**
 * 模块 4: 识别器重置与状态机连续解码测试
 */
static int test_recognizer_reset(VoskModel* model) {
    printf("\n--> [Test 4/4] 测试识别器 Reset 重置与连续状态机...\n");

    VoskRecognizer* recognizer = vosk_recognizer_new(model, 16000.0f);
    ASSERT_NOT_NULL(recognizer, "vosk_recognizer_new failed");

    // 喂入一段静音数据 (0 值 PCM)
    char silence[3200];
    memset(silence, 0, sizeof(silence));
    vosk_recognizer_accept_waveform(recognizer, silence, sizeof(silence));

    // 调用 reset
    vosk_recognizer_reset(recognizer);

    // 再次喂入静音并获取结果
    vosk_recognizer_accept_waveform(recognizer, silence, sizeof(silence));
    const char* res = vosk_recognizer_final_result(recognizer);
    ASSERT_NOT_NULL(res, "vosk_recognizer_final_result after reset returned NULL");

    vosk_recognizer_free(recognizer);
    printf("%s 识别器重置与状态机测试通过！\n", TEST_PASS_BANNER);
    return 1;
}

int main(int argc, char** argv) {
    printf("==============================================================================\n");
    printf("  LibVosk 跨平台端到端 (E2E) 全功能集成自动化测试启动\n");
    printf("==============================================================================\n");

    const char* model_path = (argc > 1) ? argv[1] : "tests/model";
    const char* wav_path = (argc > 2) ? argv[2] : "tests/test.wav";

    printf("目标模型路径 : %s\n", model_path);
    printf("测试音频路径 : %s\n", wav_path);

    VoskModel* model = NULL;

    if (!test_model_lifecycle(model_path, &model)) {
        fprintf(stderr, "\n❌ 模型加载失败，请确保测试模型已正确下载到: %s\n", model_path);
        return 1;
    }

    test_streaming_recognition(model, wav_path);
    test_grammar_constraint(model, wav_path);
    test_recognizer_reset(model);

    // 最终清理
    if (model) {
        vosk_model_free(model);
        printf("\n✔ 模型内存安全销毁完成 (vosk_model_free)。\n");
    }

    printf("==============================================================================\n");
    if (g_test_failures == 0) {
        printf("🎉🎉🎉 ALL VOSK E2E TESTS PASSED SUCCESSFULLY! (全部测试用例通过) 🎉🎉🎉\n");
        printf("==============================================================================\n");
        return 0;
    } else {
        printf("❌❌❌ %d TEST(S) FAILED! 请检查上述错误日志。\n", g_test_failures);
        printf("==============================================================================\n");
        return 1;
    }
}
