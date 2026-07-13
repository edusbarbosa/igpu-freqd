# igpu-freqd

[🇺🇸 Read this in English](README.md)

Este é um daemon em espaço de usuário (userspace) escrito em Bash que gerencia dinamicamente a frequência da GPU integrada Intel (iGPU) através do sysfs do kernel. Ao invés de travar a frequência em um valor fixo, ele ajusta continuamente a frequência mínima permitida (gt_min_freq_mhz) com base na carga de trabalho e na temperatura do pacote, equilibrando desempenho e aquecimento.

## Por que isso existe?

Eu criei essa ferramenta porque meu laptop Acer, com placa de vídeo Intel HD Graphics integrada, estava com desempenho extremamente baixo (menos de 100 FPS) em jogos leves como o Counter-Strike 1.6. Estava usando Windows e decidi migrar para o Nobara Linux (7.1.3-200.nobara.fc44.x86_64) para ver se algo mudava. Para minha surpresa, a performance terrível continuou lá. Ao estudar com mais calma, monitorando o clock e a temperatura da GPU, descobri que aparentemente alguns OEMs não estão lidando bem com o boost automático da GPU em jogos, mesmo quando a temperatura está normal. No meu caso, o clock ficava estático em 300MHz. Sem outra alternativa, dediquei alguns dias a este projeto, que felizmente solucionou meu problema! O FPS se tornou alto, a temperatura continua estável, sem stuttering ou latência excessiva.

## Como funciona?

O script utiliza vários parâmetros (taxa de polling, limites de temperatura, histerese, fatores de suavização, etc.) que possuem valores definidos por padrão e são customizáveis pelo arquivo localizado em /etc/igpu-freqd.conf. Em seguida, obtém os dados do hardware e ajusta automaticamente alguns parâmetros dependentes que serão utilizados no cálculo da frequência. O código lê o arquivo do sensor de temperatura, converte para graus Celsius e aplica um Filtro de Média Móvel Exponencial (EMA) para suavizar picos bruscos de temperatura, bem como utiliza a porcentagem de carga aplicada à GPU para calcular a frequência mínima ideal. 

Para se tornar robusto a falhas na medição de carga (que não são feitas em tempo real, e sim a cada 0,2s para reduzir custo computacional), o daemon mantém o histórico das últimas 5 leituras. Se houver 3 leituras consecutivas de 0%, a GPU é considerada ociosa; caso contrário, utiliza-se o último valor confiável de leitura.

## Núcleo

O núcleo do daemon converte carga e temperatura em uma frequência-alvo através de duas etapas principais.

### Mapeamento da Carga

A carga da GPU ($L$, em %) é mapeada para uma frequência $f_{load}$ usando uma escala logarítmica, o que permite alta responsividade em cargas baixas e saturação suave em cargas altas:

$$f_{load} = f_{base} + \frac{f_{max} - f_{base}}{\ln(101)} \cdot \ln(L + 1)$$

onde $f_{base}$ e $f_{max}$ são as frequências mínima e máxima suportadas pela GPU.

### Compensação Térmica

Se a temperatura medida ($T$) ultrapassa o limite definido ($T_{limit}$), a frequência é atenuada exponencialmente para priorizar o resfriamento:

$$f_{final} = f_{base} + (f_{load} - f_{base}) \cdot e^{-\alpha \cdot (T - T_{limit})}$$

onde $\alpha$ é o fator de decaimento térmico (`THERMAL_DECAY_FACTOR`). Caso $T \leq T_{limit}$, $f_{final} = f_{load}$.

### Filtros de Estabilidade

Por fim, antes da aplicação, dois mecanismos evitam oscilações, a **histerese**, que faz com que a nova frequência só seja aplicada caso a diferença absoluta em relação à atual superar o limiar definido ($H$) e a **taxa de slew** que limita a variação máxima por ciclo a $S$ MHz, promovendo transições de clock menos bruscas.

## Instalação

Execute o instalador diretamente do repositório:

```bash
curl -fsSL https://raw.githubusercontent.com/edusbarbosa/igpu-freqd/main/install.sh | sudo bash
```

## Configurações

| Parâmetro | Valor padrão | Descrição |
|-----------|---------------|-----------|
| `POLL_RATE` | `0.2` | Intervalo, em segundos, para fazer a leitura da carga na GPU. |
| `TEMP_LIMIT_C` | `90` | Limite de temperatura, em graus Celsius, que será aplicado no cálculo matemático da compensação térmica. |
| `HYSTERESIS` | `30` | Limiar mínimo, em MHz, que o clock atual deve possuir na diferença absoluta com a nova frequência-alvo para aplicar a mudança. |
| `INTEL_GPU_TOP_TIMEOUT` | `0.3` | Tempo máximo de espera, em segundos, para a leitura do comando `intel_gpu_top` antes de abortar (`timeout`). |
| `INTEL_GPU_TOP_SAMPLES` | `100` | Quantidade de amostras coletadas pelo `intel_gpu_top` durante a leitura para definir o uso da GPU. |
| `FALLBACK_FREQ_MHZ` | `800` | Frequência de segurança, em MHz, que será aplicada caso o script falhe repetidamente ao tentar ler a carga da placa. |
| `MAX_FAILURES` | `3` | Número máximo de falhas consecutivas de leitura toleradas antes de acionar a frequência de segurança (`fallback`). |
| `SMOOTHING_WINDOW` | `5` | Tamanho da janela (número de ciclos) usada para calcular a média móvel da carga da GPU, ignorando picos irreais curtos. |
| `ALPHA_TEMP` | `0.3` | Fator de suavização (de 0 a 1) da média móvel exponencial da temperatura, evitando que o script reaja a oscilações bruscas do sensor. |
| `SLEW_RATE_LIMIT` | `80` | Limite máximo, em MHz, que o clock pode subir ou descer em um único ciclo, forçando uma aceleração/desaceleração suave. |
| `THERMAL_DECAY_FACTOR` | `0.05` | Fator multiplicador da fórmula exponencial, que dita a agressividade do corte de clock ao ultrapassar o limite de temperatura. |
| `LOG_LEVEL` | `1` | Nível de detalhamento dos registros enviados ao `journalctl` (ex: `1` para resumos de operação, `2` para debug completo). |
| `HEARTBEAT_CYCLES` | `10` | Quantidade de ciclos consecutivos sem alterações de clock necessários para emitir um log de "sinal de vida" mostrando que o script não travou. |

## Desinstalação

Se você desejar remover completamente o `igpu-freqd` e todos os seus arquivos de configuração do sistema, execute os seguintes comandos:

```bash
sudo systemctl disable --now igpu-freqd.service
sudo rm -f /etc/systemd/system/igpu-freqd.service
sudo rm -f /usr/local/bin/igpu-freqd
sudo rm -f /etc/igpu-freqd.conf
sudo systemctl daemon-reload
```

## Contribuindo

Contribuições são sempre muito bem-vindas! Se você encontrou um bug, tem alguma ideia para melhorar ou otimizar o código, sinta-se à vontade para colaborar!
