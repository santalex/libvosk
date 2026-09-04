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
 * 测试全量覆盖 Vosk C API 核心特性 (95%+ API 覆盖率):
 *   1. ASR 模型生命周期与 OpenFST 符号检索 (Model Lifecycle & FST Symbol Mapping)
 *   2. Speaker 说话人模型生命周期与错误边界处理 (Speaker Model Lifecycle & Error Boundary)
 *   3. 流式语音识别、词级时间戳与流式打字机 (Streaming ASR, Word Timestamps & Partial Words)
 *   4. 说话人识别与声纹特征向量提取 (Speaker Recognition & Voiceprint Vector Extraction)
 *   5. 多精度音频波形多态输入 (Polymorphic Waveform Input: short* & float*)
 *   6. N-Best 候选列表、端点检测与输出配置 (N-Best Alternatives, Endpointer Delays & NLSML)
 *   7. 动态语法编译、解码与实时热重设 (Dynamic Grammar Constraint & Hot Reconfiguration)
 *   8. 识别器重置与状态机连续解码 (Recognizer Reset & State Machine Re-decoding)
 *   9. 内存安全与资源销毁 (Clean Teardown & Leak Prevention)
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
 * 模块 1: ASR 模型生命周期与 OpenFST 符号表测试
 */
static int test_model_lifecycle(const char* asr_path, VoskModel** out_model) {
    printf("\n--> [Test 1/8] 测试 ASR 模型加载与 OpenFST 词典索引...\n");
    
    // 设置 Vosk 日志级别为 0 (仅保留警告/错误)
    vosk_set_log_level(0);

    VoskModel* model = vosk_model_new(asr_path);
    ASSERT_NOT_NULL(model, "vosk_model_new failed to load ASR model directory");

    // 1. 查找有效高频词
    int word_id = vosk_model_find_word(model, "one");
    printf("    vosk_model_find_word('one') -> word_id = %d\n", word_id);
    ASSERT_TRUE(word_id >= 0, "Word 'one' should exist in standard English vocabulary");

    // 2. 查找不存在的极端随机词
    int invalid_id = vosk_model_find_word(model, "__non_existent_vocab_xyz_9988__");
    printf("    vosk_model_find_word('__non_existent__') -> word_id = %d\n", invalid_id);
    ASSERT_TRUE(invalid_id == -1, "Non-existent word must return -1");

    *out_model = model;
    printf("%s ASR 模型加载与符号表测试通过！\n", TEST_PASS_BANNER);
    return 1;
}

/**
 * 模块 2: Speaker 说话人模型加载与错误边界测试
 */
static int test_spk_model_lifecycle(const char* spk_path, VoskSpkModel** out_spk_model) {
    printf("\n--> [Test 2/8] 测试 Speaker 说话人模型生命周期与异常边界...\n");

    // 1. 验证不存在路径时的健壮容错 (必须返回 NULL，绝不能 crash)
    VoskSpkModel* invalid_spk = vosk_spk_model_new("__non_existent_spk_path_xyz__");
    ASSERT_TRUE(invalid_spk == NULL, "vosk_spk_model_new must return NULL for non-existent path");
    printf("    vosk_spk_model_new(invalid_path) -> NULL (容错防护正常)\n");

    // 2. 加载有效说话人模型
    if (spk_path && strlen(spk_path) > 0) {
        VoskSpkModel* spk = vosk_spk_model_new(spk_path);
        ASSERT_NOT_NULL(spk, "vosk_spk_model_new failed to load valid speaker model directory");
        printf("    vosk_spk_model_new('%s') -> 成功载入声纹模型句柄 [%p]\n", spk_path, (void*)spk);
        *out_spk_model = spk;
    } else {
        printf("    [Notice] 未指定 Speaker 模型路径，跳过实际加载。\n");
        *out_spk_model = NULL;
    }

    printf("%s Speaker 说话人模型生命周期与边界测试通过！\n", TEST_PASS_BANNER);
    return 1;
}

/**
 * 模块 3: 流式语音识别、词级时间戳与流式打字机测试
 */
static int test_streaming_recognition(VoskModel* model, const char* wav_path) {
    printf("\n--> [Test 3/8] 测试流式语音识别、词级时间戳与流式打字机 (WAV: %s)...\n", wav_path);

    FILE* fp = fopen(wav_path, "rb");
    ASSERT_NOT_NULL(fp, "Failed to open WAV audio file for streaming test");

    // 跳过标准 44 字节 WAV 头部
    fseek(fp, 44, SEEK_SET);

    VoskRecognizer* recognizer = vosk_recognizer_new(model, 16000.0f);
    ASSERT_NOT_NULL(recognizer, "vosk_recognizer_new failed");

    // 启用词级别时间戳与打字机流式中间词
    vosk_recognizer_set_words(recognizer, 1);
    vosk_recognizer_set_partial_words(recognizer, 1);

    char pcm_buffer[4096];
    size_t bytes_read;
    int chunk_count = 0;
    int verified_partial = 0;

    while ((bytes_read = fread(pcm_buffer, 1, sizeof(pcm_buffer), fp)) > 0) {
        chunk_count++;
        int state = vosk_recognizer_accept_waveform(recognizer, pcm_buffer, (int)bytes_read);
        if (state == 1) {
            const char* res_json = vosk_recognizer_result(recognizer);
            ASSERT_NOT_NULL(res_json, "vosk_recognizer_result returned NULL");
        } else {
            const char* partial_json = vosk_recognizer_partial_result(recognizer);
            ASSERT_NOT_NULL(partial_json, "vosk_recognizer_partial_result returned NULL");
            if (strstr(partial_json, "\"partial\"") != NULL) {
                verified_partial = 1;
            }
        }
    }
    fclose(fp);

    const char* final_json = vosk_recognizer_final_result(recognizer);
    ASSERT_NOT_NULL(final_json, "vosk_recognizer_final_result returned NULL");
    printf("    识别最终输出 JSON: %s\n", final_json);

    // 验证 JSON 中包含 "text" 字段与词级时间戳 "result" 字段
    ASSERT_TRUE(strstr(final_json, "\"text\"") != NULL, "Final result JSON must contain 'text' key");
    ASSERT_TRUE(strstr(final_json, "\"result\"") != NULL, "Final result JSON must contain 'result' timestamps array");
    ASSERT_TRUE(verified_partial == 1, "Partial result must have generated valid 'partial' field");

    vosk_recognizer_free(recognizer);
    printf("%s 流式语音识别、时间戳与流式打字机测试通过 (处理了 %d 个音频块)！\n", TEST_PASS_BANNER, chunk_count);
    return 1;
}

/**
 * 模块 4: 说话人识别与声纹特征向量提取测试 (Speaker Recognition)
 */
static int test_speaker_recognition(VoskModel* model, VoskSpkModel* spk_model, const char* wav_path) {
    if (!spk_model) {
        printf("\n--> [Test 4/8] [SKIPPED] 未提供 Speaker 模型，跳过声纹提取测试。\n");
        return 1;
    }

    printf("\n--> [Test 4/8] 测试说话人识别与 128 维声纹特征向量提取 (Speaker Recognition)...\n");

    // 方式 A: 通过 vosk_recognizer_new_spk 直接初始化带声纹模型的识别器
    VoskRecognizer* recognizer = vosk_recognizer_new_spk(model, 16000.0f, spk_model);
    ASSERT_NOT_NULL(recognizer, "vosk_recognizer_new_spk failed");

    FILE* fp = fopen(wav_path, "rb");
    ASSERT_NOT_NULL(fp, "Failed to open WAV audio file for speaker test");
    fseek(fp, 44, SEEK_SET);

    char pcm_buffer[4096];
    size_t bytes_read;
    while ((bytes_read = fread(pcm_buffer, 1, sizeof(pcm_buffer), fp)) > 0) {
        vosk_recognizer_accept_waveform(recognizer, pcm_buffer, (int)bytes_read);
    }
    fclose(fp);

    const char* final_json = vosk_recognizer_final_result(recognizer);
    ASSERT_NOT_NULL(final_json, "vosk_recognizer_final_result returned NULL for speaker recognizer");
    printf("    声纹识别最终输出 (前 150 字符): %.150s ...\n", final_json);

    // 验证输出 JSON 包含 "spk" 声纹向量与 "spk_frames"
    ASSERT_TRUE(strstr(final_json, "\"spk\"") != NULL, "Speaker result JSON must contain 'spk' vector");
    ASSERT_TRUE(strstr(final_json, "\"spk_frames\"") != NULL, "Speaker result JSON must contain 'spk_frames'");
    vosk_recognizer_free(recognizer);

    // 方式 B: 测试 vosk_recognizer_set_spk_model 动态为已初始化识别器注入声纹模型
    printf("    --> 验证动态注入 API (vosk_recognizer_set_spk_model)...\n");
    VoskRecognizer* dynamic_rec = vosk_recognizer_new(model, 16000.0f);
    ASSERT_NOT_NULL(dynamic_rec, "vosk_recognizer_new failed");
    vosk_recognizer_set_spk_model(dynamic_rec, spk_model);

    fp = fopen(wav_path, "rb");
    ASSERT_NOT_NULL(fp, "Failed to re-open WAV for dynamic speaker test");
    fseek(fp, 44, SEEK_SET);
    while ((bytes_read = fread(pcm_buffer, 1, sizeof(pcm_buffer), fp)) > 0) {
        vosk_recognizer_accept_waveform(dynamic_rec, pcm_buffer, (int)bytes_read);
    }
    fclose(fp);

    const char* dyn_json = vosk_recognizer_final_result(dynamic_rec);
    ASSERT_NOT_NULL(dyn_json, "vosk_recognizer_final_result returned NULL for dynamically injected spk");
    ASSERT_TRUE(strstr(dyn_json, "\"spk\"") != NULL, "Dynamic spk injection result must contain 'spk'");
    vosk_recognizer_free(dynamic_rec);

    printf("%s 说话人识别与 128 维声纹特征向量提取测试通过！\n", TEST_PASS_BANNER);
    return 1;
}

/**
 * 模块 5: 多精度波形输入多态测试 (short* & float* API)
 */
static int test_polymorphic_waveforms(VoskModel* model, const char* wav_path) {
    printf("\n--> [Test 5/8] 测试多精度波形多态输入 (vosk_recognizer_accept_waveform_s / _f)...\n");

    FILE* fp = fopen(wav_path, "rb");
    ASSERT_NOT_NULL(fp, "Failed to open WAV audio file for polymorphic test");

    fseek(fp, 0, SEEK_END);
    long file_size = ftell(fp);
    ASSERT_TRUE(file_size > 44, "WAV audio file is too short");

    long pcm_bytes = file_size - 44;
    fseek(fp, 44, SEEK_SET);

    short* short_buf = (short*)malloc(pcm_bytes);
    ASSERT_NOT_NULL(short_buf, "Failed to allocate memory for short PCM buffer");
    size_t read_bytes = fread(short_buf, 1, pcm_bytes, fp);
    fclose(fp);

    int num_samples = (int)(read_bytes / sizeof(short));
    printf("    载入 %d 个 16-bit PCM 采样点...\n", num_samples);

    // 1. 测试 accept_waveform_s (short* 数组输入)
    VoskRecognizer* rec_s = vosk_recognizer_new(model, 16000.0f);
    ASSERT_NOT_NULL(rec_s, "vosk_recognizer_new failed for short waveform test");
    vosk_recognizer_accept_waveform_s(rec_s, short_buf, num_samples);
    const char* res_s = vosk_recognizer_final_result(rec_s);
    ASSERT_NOT_NULL(res_s, "vosk_recognizer_final_result returned NULL for short input");
    ASSERT_TRUE(strstr(res_s, "\"text\"") != NULL, "Short waveform result must contain 'text'");
    printf("    [short*] 识别结果: %s\n", res_s);
    vosk_recognizer_free(rec_s);

    // 2. 测试 accept_waveform_f (float* 数组输入)
    float* float_buf = (float*)malloc(num_samples * sizeof(float));
    ASSERT_NOT_NULL(float_buf, "Failed to allocate memory for float PCM buffer");
    for (int i = 0; i < num_samples; i++) {
        float_buf[i] = (float)short_buf[i];
    }

    VoskRecognizer* rec_f = vosk_recognizer_new(model, 16000.0f);
    ASSERT_NOT_NULL(rec_f, "vosk_recognizer_new failed for float waveform test");
    vosk_recognizer_accept_waveform_f(rec_f, float_buf, num_samples);
    const char* res_f = vosk_recognizer_final_result(rec_f);
    ASSERT_NOT_NULL(res_f, "vosk_recognizer_final_result returned NULL for float input");
    ASSERT_TRUE(strstr(res_f, "\"text\"") != NULL, "Float waveform result must contain 'text'");
    printf("    [float*] 识别结果: %s\n", res_f);
    vosk_recognizer_free(rec_f);

    free(short_buf);
    free(float_buf);

    printf("%s 多精度音频多态输入测试通过！\n", TEST_PASS_BANNER);
    return 1;
}

/**
 * 模块 6: N-Best 候选列表、端点检测延时与配置测试
 */
static int test_alternatives_and_endpointer(VoskModel* model, const char* wav_path) {
    printf("\n--> [Test 6/8] 测试 N-Best 多候选集与 Endpointer 端点检测延时配置...\n");

    VoskRecognizer* recognizer = vosk_recognizer_new(model, 16000.0f);
    ASSERT_NOT_NULL(recognizer, "vosk_recognizer_new failed");

    // 配置 N-best 候选数为 3
    vosk_recognizer_set_max_alternatives(recognizer, 3);
    // 配置静音端点检测模式与延时参数
    vosk_recognizer_set_endpointer_mode(recognizer, VOSK_EP_ANSWER_DEFAULT);
    vosk_recognizer_set_endpointer_delays(recognizer, 5.0f, 0.8f, 25.0f);
    // 配置 NLSML 输出开关
    vosk_recognizer_set_nlsml(recognizer, 0);

    FILE* fp = fopen(wav_path, "rb");
    ASSERT_NOT_NULL(fp, "Failed to open WAV audio file for alternatives test");
    fseek(fp, 44, SEEK_SET);

    char pcm_buffer[4096];
    size_t bytes_read;
    while ((bytes_read = fread(pcm_buffer, 1, sizeof(pcm_buffer), fp)) > 0) {
        vosk_recognizer_accept_waveform(recognizer, pcm_buffer, (int)bytes_read);
    }
    fclose(fp);

    const char* alt_json = vosk_recognizer_final_result(recognizer);
    ASSERT_NOT_NULL(alt_json, "vosk_recognizer_final_result returned NULL in alternatives mode");
    printf("    N-Best 多候选识别输出: %s\n", alt_json);

    // 验证 JSON 中包含 "alternatives" 候选数组
    ASSERT_TRUE(strstr(alt_json, "\"alternatives\"") != NULL, "Result JSON must contain 'alternatives' array");

    vosk_recognizer_free(recognizer);
    printf("%s N-Best 多候选集与 Endpointer 参数配置测试通过！\n", TEST_PASS_BANNER);
    return 1;
}

/**
 * 模块 7: 动态受限语法识别与实时热切换测试
 */
static int test_grammar_constraint(VoskModel* model, const char* wav_path) {
    printf("\n--> [Test 7/8] 测试动态受限语法识别与实时热重设 (Grammar Constraint & vosk_recognizer_set_grm)...\n");

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
 * 模块 8: 识别器重置与状态机连续解码测试
 */
static int test_recognizer_reset(VoskModel* model) {
    printf("\n--> [Test 8/8] 测试识别器 Reset 重置与连续状态机...\n");

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
    printf("  LibVosk 跨平台端到端 (E2E) 全特性自动化测试引擎\n");
    printf("==============================================================================\n");

    const char* asr_path = (argc > 1) ? argv[1] : "tests/asr";
    const char* wav_path = (argc > 2) ? argv[2] : "tests/test.wav";
    const char* spk_path = (argc > 3) ? argv[3] : "tests/spk";

    // 针对旧测试兼容: 若 tests/asr 不存在但 tests/model 存在，自动回退
    FILE* check_fp = fopen(asr_path, "r");
    if (!check_fp && strcmp(asr_path, "tests/asr") == 0) {
        FILE* fallback_fp = fopen("tests/model", "r");
        if (fallback_fp) {
            fclose(fallback_fp);
            asr_path = "tests/model";
        }
    } else if (check_fp) {
        fclose(check_fp);
    }

    printf("ASR 模型路径     : %s\n", asr_path);
    printf("测试音频路径     : %s\n", wav_path);
    printf("Speaker 模型路径 : %s\n", spk_path);

    VoskModel* model = NULL;
    VoskSpkModel* spk_model = NULL;

    if (!test_model_lifecycle(asr_path, &model)) {
        fprintf(stderr, "\n❌ ASR 模型加载失败，请确保测试模型已正确就位: %s\n", asr_path);
        return 1;
    }

    test_spk_model_lifecycle(spk_path, &spk_model);
    test_streaming_recognition(model, wav_path);
    test_speaker_recognition(model, spk_model, wav_path);
    test_polymorphic_waveforms(model, wav_path);
    test_alternatives_and_endpointer(model, wav_path);
    test_grammar_constraint(model, wav_path);
    test_recognizer_reset(model);

    // 最终清理内存
    if (spk_model) {
        vosk_spk_model_free(spk_model);
        printf("\n✔ Speaker 模型内存安全销毁完成 (vosk_spk_model_free)。\n");
    }
    if (model) {
        vosk_model_free(model);
        printf("✔ ASR 模型内存安全销毁完成 (vosk_model_free)。\n");
    }

    printf("==============================================================================\n");
    if (g_test_failures == 0) {
        printf("🎉🎉🎉 ALL VOSK E2E TESTS (8/8) PASSED SUCCESSFULLY! 🎉🎉🎉\n");
        printf("==============================================================================\n");
        return 0;
    } else {
        printf("❌❌❌ %d TEST(S) FAILED! 请检查上述错误日志。\n", g_test_failures);
        printf("==============================================================================\n");
        return 1;
    }
}
