import os
import sys
import platform
import cffi
import json

_cffi_ffi = cffi.FFI()
_cffi_ffi.cdef("""
    typedef struct VoskModel VoskModel;
    typedef struct VoskSpkModel VoskSpkModel;
    typedef struct VoskRecognizer VoskRecognizer;

    VoskModel *vosk_model_new(const char *model_path);
    void vosk_model_free(VoskModel *model);
    
    VoskSpkModel *vosk_spk_model_new(const char *model_path);
    void vosk_spk_model_free(VoskSpkModel *model);

    VoskRecognizer *vosk_recognizer_new(VoskModel *model, float sample_rate);
    VoskRecognizer *vosk_recognizer_new_spk(VoskModel *model, float sample_rate, VoskSpkModel *spk_model);
    VoskRecognizer *vosk_recognizer_new_grm(VoskModel *model, float sample_rate, const char *grammar);
    
    void vosk_recognizer_free(VoskRecognizer *recognizer);
    void vosk_recognizer_set_max_alternatives(VoskRecognizer *recognizer, int max_alternatives);
    void vosk_recognizer_set_words(VoskRecognizer *recognizer, int words);
    void vosk_recognizer_set_spk_model(VoskRecognizer *recognizer, VoskSpkModel *spk_model);

    int vosk_recognizer_accept_waveform(VoskRecognizer *recognizer, const char *data, int length);
    int vosk_recognizer_accept_waveform_s(VoskRecognizer *recognizer, const short *data, int length);
    int vosk_recognizer_accept_waveform_f(VoskRecognizer *recognizer, const float *data, int length);

    const char *vosk_recognizer_result(VoskRecognizer *recognizer);
    const char *vosk_recognizer_partial_result(VoskRecognizer *recognizer);
    const char *vosk_recognizer_final_result(VoskRecognizer *recognizer);
    void vosk_recognizer_reset(VoskRecognizer *recognizer);

    void vosk_set_log_level(int log_level);
""")

def _load_library():
    package_dir = os.path.dirname(__file__)
    
    # 1. First attempt: check direct files in package directory
    possible_names = ["libvosk.dylib", "libvosk.so", "libvosk.dll"]
    for name in possible_names:
        lib_path = os.path.join(package_dir, name)
        if os.path.exists(lib_path):
            try:
                return _cffi_ffi.dlopen(lib_path)
            except Exception:
                pass

    # 2. Second attempt: search in multi-platform directory (lib/<os>_<arch>/...)
    system = platform.system().lower()
    machine = platform.machine().lower()
    
    if system == "darwin":
        os_tag = "macos"
    elif system == "windows":
        os_tag = "windows"
    else:
        os_tag = "linux"
        
    arch_tag = machine
    if machine in ["x86_64", "amd64"]:
        arch_tag = "x86_64"
    elif machine in ["aarch64", "arm64"]:
        arch_tag = "arm64"
    elif machine in ["i386", "i686", "x86"]:
        arch_tag = "x86"

    # Search matching dynamic library in lib directory
    lib_dir = os.path.join(package_dir, "lib")
    if os.path.exists(lib_dir):
        for root, _, files in os.walk(lib_dir):
            for file in files:
                if file.endswith((".dylib", ".so", ".dll")):
                    full_path = os.path.join(root, file)
                    if os_tag in root.lower() or arch_tag in root.lower():
                        try:
                            return _cffi_ffi.dlopen(full_path)
                        except Exception:
                            pass

    # 3. Fallback: search system dynamic library paths
    for name in possible_names:
        try:
            return _cffi_ffi.dlopen(name)
        except Exception:
            pass

    raise RuntimeError("Could not load libvosk shared library for your platform.")

_lib = _load_library()

def set_log_level(level):
    _lib.vosk_set_log_level(level)

class Model:
    def __init__(self, model_path):
        if not os.path.exists(model_path):
            raise FileNotFoundError(f"Model path {model_path} does not exist")
        self._cptr = _lib.vosk_model_new(model_path.encode('utf-8'))
        if self._cptr == _cffi_ffi.NULL:
            raise RuntimeError("Failed to create Vosk model")

    def __del__(self):
        if hasattr(self, '_cptr') and self._cptr != _cffi_ffi.NULL:
            _lib.vosk_model_free(self._cptr)

class SpkModel:
    def __init__(self, model_path):
        if not os.path.exists(model_path):
            raise FileNotFoundError(f"Speaker model path {model_path} does not exist")
        self._cptr = _lib.vosk_spk_model_new(model_path.encode('utf-8'))
        if self._cptr == _cffi_ffi.NULL:
            raise RuntimeError("Failed to create Vosk speaker model")

    def __del__(self):
        if hasattr(self, '_cptr') and self._cptr != _cffi_ffi.NULL:
            _lib.vosk_spk_model_free(self._cptr)

class KaldiRecognizer:
    def __init__(self, *args):
        if len(args) == 2 and isinstance(args[0], Model):
            self._cptr = _lib.vosk_recognizer_new(args[0]._cptr, float(args[1]))
        elif len(args) == 3 and isinstance(args[0], Model) and isinstance(args[2], SpkModel):
            self._cptr = _lib.vosk_recognizer_new_spk(args[0]._cptr, float(args[1]), args[2]._cptr)
        elif len(args) == 3 and isinstance(args[0], Model) and isinstance(args[2], str):
            self._cptr = _lib.vosk_recognizer_new_grm(args[0]._cptr, float(args[1]), args[2].encode('utf-8'))
        else:
            raise TypeError("Invalid arguments for KaldiRecognizer initialization")

        if self._cptr == _cffi_ffi.NULL:
            raise RuntimeError("Failed to create KaldiRecognizer")

    def __del__(self):
        if hasattr(self, '_cptr') and self._cptr != _cffi_ffi.NULL:
            _lib.vosk_recognizer_free(self._cptr)

    def SetMaxAlternatives(self, max_alternatives):
        _lib.vosk_recognizer_set_max_alternatives(self._cptr, max_alternatives)

    def SetWords(self, words):
        _lib.vosk_recognizer_set_words(self._cptr, 1 if words else 0)

    def SetSpkModel(self, spk_model):
        _lib.vosk_recognizer_set_spk_model(self._cptr, spk_model._cptr)

    def AcceptWaveform(self, data):
        if isinstance(data, bytes):
            return _lib.vosk_recognizer_accept_waveform(self._cptr, data, len(data)) != 0
        raise TypeError("Audio data must be bytes")

    def Result(self):
        res = _lib.vosk_recognizer_result(self._cptr)
        return _cffi_ffi.string(res).decode('utf-8')

    def PartialResult(self):
        res = _lib.vosk_recognizer_partial_result(self._cptr)
        return _cffi_ffi.string(res).decode('utf-8')

    def FinalResult(self):
        res = _lib.vosk_recognizer_final_result(self._cptr)
        return _cffi_ffi.string(res).decode('utf-8')

    def Reset(self):
        _lib.vosk_recognizer_reset(self._cptr)
