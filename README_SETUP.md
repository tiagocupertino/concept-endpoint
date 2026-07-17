# concept-endpoint — setup (Caminho B: imagem via CI)

Worker FLUX.2 pra concept-gen geometry-locked (ControlNet-Union). Você configura o repo/registry **1×**;
depois eu (Claude) crio o endpoint na RunPod e valido. Modelos ficam no network volume; a imagem carrega
os custom nodes (que o volume não consegue carregar).

## O que tem aqui
```
Dockerfile            worker-comfyui + 6 custom nodes (ControlNet-Union + preprocessors + upscale + utils)
bootstrap_models.sh   baixa os ~45GB de FLUX.2 pro volume no 1º boot (idempotente + torna portável entre DCs)
.github/workflows/    GitHub Actions: builda a imagem e publica no GHCR (usa o GITHUB_TOKEN nativo, sem secret)
workflows/            workflow ComfyUI (API) que o endpoint executa
```

## Passo a passo (teu, ~5 min + ~40 min de build automático)

1. **Cria um repo no GitHub** (ex.: `concept-endpoint`), pode ser privado.

2. **Sobe estes arquivos** pro repo (branch `main`). Do teu lado, de dentro desta pasta:
   ```bash
   cd /home/pipeline/deploy/concept-endpoint
   git init && git add -A && git commit -m "concept-gen FLUX.2 worker"
   git branch -M main
   git remote add origin git@github.com:<SEU_USUARIO>/concept-endpoint.git
   git push -u origin main
   ```
   > O push já dispara o build (Actions → aba "Actions" no GitHub). Leva ~30-40 min (base CUDA + nodes).

3. **Torna o package público** (1 clique, pra RunPod puxar sem login):
   GitHub → teu perfil → **Packages** → `concept-endpoint` → **Package settings** → **Change visibility** → **Public**.

4. **Me passa o nome da imagem**: `ghcr.io/<SEU_USUARIO>/concept-endpoint:latest`
   (fica minúsculo). Com isso eu crio o endpoint apontando pro volume `concept-flux` (US-MO-2) e rodo o teste.

## O que EU faço depois que você me passar a imagem
- `create-endpoint`: imagem GHCR + volume `wewf905htg` + pool `BLACKWELL_96` (RTX PRO 6000) + FlashBoot + scale-to-zero.
- 1º job = baixa os modelos pro volume (~5 min, 1×) + gera a 1ª imagem do `mining_equipment` → valido o geometry-lock.
- Depois: `burst_client.py` (fila de concepts) + `bench_gpu.py` (crava $/img por GPU, ver `docs/GPU_BENCHMARK_PLAN.md`).

## Portabilidade (tua pergunta do Canadá)
A imagem é global (roda em qualquer DC). Pra rodar noutra região é só: criar um volume novo lá + apontar o
endpoint pro novo DC/pool — o `bootstrap_models.sh` repopula sozinho no 1º boot. Config idêntica, só muda a infra.

## Trocar/atualizar nodes ou modelos depois
- Node novo → adiciona 1 linha de `git clone` no `Dockerfile`, push → Actions rebuilda.
- Modelo novo → adiciona 1 linha `dl ...` no `bootstrap_models.sh` (ou eu jogo direto no volume).
