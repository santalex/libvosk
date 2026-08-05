import os
from setuptools import setup, find_packages

version = os.environ.get("VOSK_TAG", "0.3.50").lstrip("v")

setup(
    name="libvosk",
    version=version,
    description="Offline speech recognition API for Python",
    long_description="High-performance offline speech recognition library for Python based on Vosk C API.",
    long_description_content_type="text/markdown",
    author="Vosk API Multi-Platform Prebuilt Project",
    url="https://github.com/alphacep/vosk-api",
    packages=find_packages(),
    package_data={
        "vosk": [
            "*.so", "*.dylib", "*.dll",
            "lib/*/*.so", "lib/*/*.dylib", "lib/*/*.dll",
            "lib/*/*/*.so", "lib/*/*/*.dylib", "lib/*/*/*.dll"
        ],
    },
    include_package_data=True,
    install_requires=[
        "cffi>=1.0.0",
    ],
    classifiers=[
        "Programming Language :: Python :: 3",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
    ],
    python_requires=">=3.7",
)
