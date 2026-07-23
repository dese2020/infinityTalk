# Use specific version of nvidia cuda image
FROM wlsdml1114/engui_genai-base_blackwell:1.1 as runtime

# wget 설치 (URL 다운로드를 위해)
RUN apt-get update && apt-get install -y wget && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir -U "huggingface_hub[hf_xet]"
RUN pip install --no-cache-dir runpod websocket-client librosa

# La imagen base trae torch 2.9.1+cu128. En una RTX 5090 (Blackwell) los kernels
# optimizados de comfy_kitchen requieren cu130+; sin esto corre en el backend
# "eager" (más lento, visto en logs: "comfy_kitchen backend cuda ... disabled: True").
# Descomenta si tu base image aún no trae cu130:
# RUN pip install --no-cache-dir --pre torch torchvision torchaudio \
#     --index-url https://download.pytorch.org/whl/nightly/cu130

WORKDIR /

RUN git clone https://github.com/comfyanonymous/ComfyUI.git && \
    cd /ComfyUI && \
    pip install -r requirements.txt

RUN cd /ComfyUI/custom_nodes && \
    git clone https://github.com/city96/ComfyUI-GGUF && \
    cd ComfyUI-GGUF && \
    pip install -r requirements.txt

RUN cd /ComfyUI/custom_nodes && \
    git clone https://github.com/kijai/ComfyUI-KJNodes && \
    cd ComfyUI-KJNodes && \
    pip install -r requirements.txt

RUN cd /ComfyUI/custom_nodes && \
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite && \
    cd ComfyUI-VideoHelperSuite && \
    pip install -r requirements.txt
    
RUN cd /ComfyUI/custom_nodes && \
    git clone https://github.com/orssorbit/ComfyUI-wanBlockswap

RUN cd /ComfyUI/custom_nodes && \
    git clone https://github.com/kijai/ComfyUI-MelBandRoFormer && \
    cd ComfyUI-MelBandRoFormer && \
    pip install -r requirements.txt

RUN cd /ComfyUI/custom_nodes && \
    git clone https://github.com/kijai/ComfyUI-WanVideoWrapper && \
    cd ComfyUI-WanVideoWrapper && \
    pip install -r requirements.txt


# Descargas via huggingface_hub. Xet (hf_xet) reemplaza al viejo hf_transfer
# (deprecado, visto en logs: "HF_HUB_ENABLE_HF_TRANSFER ... is deprecated").
#  Copiamos el archivo real en destino (no symlink al cache), y al final
# borramos el cache de HF para que no quede duplicado dentro de la imagen.
ENV HF_XET_HIGH_PERFORMANCE=1
ENV HF_HUB_VERBOSITY=warning

RUN hf download Kijai/WanVideo_comfy_fp8_scaled InfiniteTalk/Wan2_1-InfiniteTalk-Single_fp8_e4m3fn_scaled_KJ.safetensors --local-dir /ComfyUI/models/diffusion_models  && \
    hf download Kijai/WanVideo_comfy_fp8_scaled InfiniteTalk/Wan2_1-InfiniteTalk-Multi_fp8_e4m3fn_scaled_KJ.safetensors --local-dir /ComfyUI/models/diffusion_models  && \
    hf download Kijai/WanVideo_comfy Wan2_1-I2V-14B-480P_fp8_e4m3fn.safetensors --local-dir /ComfyUI/models/diffusion_models  && \
    hf download Kijai/WanVideo_comfy Lightx2v/lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors --local-dir /ComfyUI/models/loras  && \
    hf download hijdese2020/wan21_data generalnsfw/wan-nsfw-e14-fixed.safetensors --repo-type dataset --local-dir /ComfyUI/models/loras  && \
    hf download Kijai/WanVideo_comfy Wan2_1_VAE_bf16.safetensors --local-dir /ComfyUI/models/vae  && \
    hf download Kijai/WanVideo_comfy umt5-xxl-enc-fp8_e4m3fn.safetensors --local-dir /ComfyUI/models/text_encoders  && \
    hf download Comfy-Org/Wan_2.1_ComfyUI_repackaged split_files/clip_vision/clip_vision_h.safetensors --local-dir /ComfyUI/models/clip_vision  && \
    hf download Kijai/MelBandRoFormer_comfy MelBandRoformer_fp16.safetensors --local-dir /ComfyUI/models/diffusion_models  && \
    hf download Kijai/wav2vec2_safetensors wav2vec2-chinese-base_fp16.safetensors --local-dir /ComfyUI/models/transformers  && \
    rm -rf /root/.cache/huggingface


COPY . .
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]