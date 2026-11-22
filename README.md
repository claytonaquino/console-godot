# Console Godot — v0.1

Um "console" que liga direto de um pendrive: Linux (Debian 12) mínimo, sem área de trabalho, que abre um menu de jogos feito em Godot e navegável pelo controle. Nada é instalado nem alterado no computador.

## O que vem nesta versão

| Parte | O que faz |
|---|---|
| `launcher/` | Menu do console (Godot 4.7): biblioteca com capas, relógio, status de rede e controles. Menu de sistema (Start) com volume, Wi-Fi com teclado virtual, pareamento Bluetooth, driver de vídeo, informações, terminal, reiniciar e desligar. Para fechar um jogo, segure Home (ou Select + Start) por 2 segundos. |
| `games/ilha-teste/` | Jogo de teste em 3D: ilha gerada por algoritmo, com árvores, água, céu, sombras e 4 horários do dia. Mostra o FPS e baixa a qualidade sozinho se o FPS ficar baixo. |
| `os/` | Configuração do Debian live (live-build): login automático, X + gerenciador de janelas de tela cheia, PipeWire, NetworkManager, Bluetooth e firmwares. Também traz o driver **NVIDIA 470**, necessário para a sua GT 730. |
| `scripts/` | `export-godot.sh` exporta os projetos Godot. `build-iso.sh` gera a imagem do pendrive. |
| `build/` | Launcher e jogo **já exportados**: não é preciso baixar o Godot para gerar a ISO. |

## Seu computador não é alterado

O console roda inteiro a partir do pendrive. O sistema foi configurado para não tocar no PC:

- **Nada é instalado no Windows:** a imagem é gerada na nuvem (GitHub) e gravada com o Rufus *portátil*, que não precisa de instalação.
- **A BIOS não é alterada:** o pendrive é escolhido pelo menu de boot de uso único (F12). O Secure Boot fica como está.
- **Os discos internos não são usados:** o sistema não monta nenhum disco do PC e não ativa swap dos discos internos. A área de saves só é procurada e criada em pendrive USB (`persistence-media=removable-usb`).
- **O relógio do Windows não muda:** o console trata o relógio do PC como hora local, igual ao Windows (`live-config.utc=no`), e não sincroniza a hora pela internet.
- **A inicialização do PC não muda:** não há instalador e nenhuma entrada de boot é gravada no computador. Sem o pendrive, o PC liga no Windows como sempre.

## 1. Gerar a imagem do pendrive (na nuvem, pelo GitHub)

1. Crie uma conta grátis em github.com, se ainda não tiver, e um repositório **público** novo (ex.: `console-godot`).
2. No repositório, clique em **Add file → Upload files** e arraste o conteúdo desta pasta, incluindo a pasta `.github`, **menos a pasta `build`**: os arquivos dela passam do limite de 25 MB do envio pelo navegador, e o GitHub gera essa pasta de novo. Depois clique em *Commit changes*.
   - Se a pasta `.github` não for enviada pelo navegador, crie o arquivo pelo botão **Add file → Create new file** com o nome `.github/workflows/build-iso.yml` e cole o conteúdo do arquivo de mesmo nome.
3. Abra a aba **Actions**, escolha **"Gerar ISO do console"** e clique em **Run workflow**. Leva de 30 a 60 minutos.
4. Quando terminar, a ISO aparece na aba **Releases**. Baixe o arquivo `.iso`.

Opção: marque "Gerar sem o driver NVIDIA 470" para uma imagem menor, para PCs com AMD ou Intel.

> Se você usa Linux em outro computador, também dá para gerar localmente: `sudo apt install live-build curl unzip` e depois `sudo ./scripts/build-iso.sh`.

## 2. Gravar no pendrive

- Pendrive **USB 3 de 16 GB ou mais** (32 GB recomendado). **Tudo o que estiver nele será apagado.**
- Baixe o **Rufus portátil** (rufus.ie, versão "Portable"). Ele roda sem instalar nada.
- No Rufus, escolha o pendrive e a ISO e clique em *Iniciar*. Quando ele perguntar, escolha **"Gravar em modo imagem DD"**. O modo ISO não funciona com os saves.

## 3. Ligar no Dell XPS 8900

1. Com o pendrive conectado, ligue o PC apertando **F12** e escolha o pendrive (de preferência a opção "UEFI"). Isso vale só para aquela vez e não altera a BIOS.
2. **Primeiro uso:** o console cria uma área de saves **no próprio pendrive** e reinicia uma vez. Depois disso, ficam guardados saves, Wi-Fi, controles pareados e configurações.
3. **Secure Boot:** para saber se está ligado, sem mudar nada, abra no Windows `msinfo32` e veja "Estado da Inicialização Segura".
   - **Desligado:** o console usa o driver NVIDIA 470, o mais rápido para a GT 730.
   - **Ligado:** o console funciona normalmente, mas o driver NVIDIA não é assinado e fica bloqueado. Nesse caso ele usa sozinho o driver aberto (nouveau), que na GT 730 é bem mais lento. Os jogos 3D vão rodar com FPS baixo.

## 4. Usando

| Controle | Ação |
|---|---|
| Analógico / direcional | Navegar |
| A | Jogar / confirmar |
| B | Voltar |
| Start | Menu do sistema |
| Home (segurar 2 s) ou Select + Start | Fechar o jogo e voltar ao menu |
| No teclado virtual | X apaga, Y insere espaço, Start confirma |

No teclado do PC: setas, Enter, Esc, F1 (menu) e F12 (segurar para fechar o jogo).

**Ilha de Teste:** analógico esquerdo anda, direito olha, A pula, B corre, **Y muda a qualidade**, **X muda a hora do dia** e Select sai. O FPS aparece no canto superior esquerdo. Me mande esse número junto com a qualidade usada.

## 5. Vídeo: NVIDIA GT 730

- Padrão: o console tenta o **driver NVIDIA 470**. Se ele não carregar, usa o driver aberto **nouveau**.
- Para forçar o driver aberto: menu Start → "Placa NVIDIA antiga" (vale a partir da próxima inicialização). Se a tela ficar preta, aperte **e** no menu de boot, acrescente `console.gpu=nouveau` ao fim da linha `linux` e aperte F10.
- Em máquinas AMD ou Intel, nada disso importa: o driver Mesa é usado automaticamente.

## 6. Loja de jogos

Os jogos novos chegam pela **Loja de jogos** (Start → Loja de jogos), sem linha de comando:

- A loja lê o catálogo publicado no ramo **`downloads`** deste repositório (pasta `jogos/`).
- Cada jogo é baixado, conferido (SHA-256) e instalado em `~/games`, na área de saves do pendrive.
- Se a mesma versão existir na imagem e na loja, o console usa a mais nova.
- Ao ligar, o console procura novidades. O botão na loja alterna entre **só avisar**, **instalar sozinho** e **não procurar**.

**Para publicar um jogo:** coloque o projeto Godot em `games/<id>/` com um `game.json` e a versão em `project.godot` (`config/version`). Ao enviar para o `main`, o workflow **"Publicar jogos na Loja"** exporta, empacota e atualiza o catálogo. Para atualizar um jogo, aumente o `config/version`.

Formato do `game.json`:

```json
{
  "id": "meu-jogo",
  "title": "Meu Jogo",
  "description": "Uma linha sobre o jogo.",
  "exec": "meu-jogo.x86_64",
  "color": "#e76f51"
}
```

## 7. Problemas

- **Registros (logs):** `~/.config/console/launcher.log` e `xorg-session.log`, visíveis pelo Terminal do menu Start.
- **Terminal de texto:** Ctrl+Alt+F2 (se pedir login: usuário `console`, senha `live`). Ctrl+Alt+F1 volta para o console.
- **Wi-Fi não aparece:** a placa pode precisar de um firmware que não está na lista. Me mande a saída de `lspci -nn`.
- **Não quer criar a área de saves:** confira se o pendrive foi gravado no Rufus em modo DD.

## O que já foi testado e o que falta

- ✅ O launcher e a Ilha de Teste foram exportados e testados no Linux com renderização por software: menus, teclado virtual, Wi-Fi e Bluetooth simulados, e abrir e fechar o jogo.
- ✅ A criação da área de saves foi testada numa imagem de pendrive simulada. A ISO permanece intacta.
- ⏳ **A ISO ainda não foi gerada**: o ambiente onde preparei o projeto não tem acesso aos repositórios do Debian. A primeira geração será no GitHub Actions.
- ⏳ O driver NVIDIA 470, o Wi-Fi, o Bluetooth e o som reais só podem ser confirmados no seu hardware.

## Simulador de Carro (v0.1)

Física própria, calculada a 240 Hz: pneu pela fórmula de Pacejka com escorregamento combinado, suspensão independente com barra estabilizadora, motor 2.0 com curva de torque, câmbio automático ou manual, diferencial autoblocante, freios com ABS e aerodinâmica.

Medições do teste automático (`SIMCAR_TEST=physics`):

| Teste | Resultado |
|---|---|
| 0–100 km/h | 8,2 s |
| Frenagem 100–0 km/h (ABS) | 39,5 m (0,99 g) |
| Skidpad R = 40 m | 0,93 g a 69 km/h |
| Volta do piloto automático (pista de 1,9 km) | 1:16,6 |

| Controle | Teclado | Ação |
|---|---|---|
| RT / LT | W / S | Acelerar / frear (parado, segurar o freio engata a ré) |
| Analógico esquerdo | A / D | Esterçar |
| B | Espaço | Freio de mão |
| RB / LB | E / Q | Subir / descer marcha |
| Y | C | Câmera (perseguição, capô, cockpit, TV) |
| X | R | Recolocar na pista |
| Direcional ↑ | T | Telemetria dos pneus |
| Direcional ↓ | M | Câmbio automático / manual |
| Direcional ← | P | Piloto automático (demonstração) |
| Direcional → | G | Qualidade gráfica |
| — | L | Diferencial aberto / autoblocante |
| Select | Esc | Sair |

## Terra de Blocos (v0.1 — Capítulo 1)

Ação e aventura isométrica cooperativa (1 ou 2 jogadores) num mundo de blocos de brinquedo. Iara (arco) e Bento (lança) enfrentam máquinas com **pontos fracos destacáveis**: destruir uma peça muda o comportamento da máquina (sensor → fica cega, hélice → despenca, tanque → explode, canhões → expõem o núcleo do chefe).

- Vila (quadro de missões, oficina de melhorias, moradores), missão 1 "O Chamado" (alavancas, portão, parede secreta com baú, artefato, emboscada) e missão 2 "Ataque à Vila" (3 ondas + chefe Colosso de Sucata com 2 fases).
- Combo de equipe: flecha de gelo congela, golpe de lança despedaça (dano triplo).
- Animação em "stop motion" (12 quadros/s), sons sintetizados, progresso salvo.
- Teste automático: `TDB_TEST=bot` joga o capítulo inteiro sozinho (passou: ~7 min de jogo).

| Controle | Teclado | Ação |
|---|---|---|
| Analógico esquerdo | WASD | Mover |
| X (ou RT) | J | Ataque |
| A | Espaço | Rolamento / interagir na vila |
| Y | K | Especial (chuva de flechas / onda de choque) |
| B | L | Habilidade (flecha de gelo / escudo) |
| LB | Tab | Trocar herói (jogando sozinho) |
| Start | Esc | Pausa (Jogador 2 aperta Start para entrar) |

## Próximos passos

1. Testar no XPS 8900 e anotar o FPS da Ilha de Teste em cada qualidade.
2. Simulador de carro: começar pela física (pneus, suspensão, câmbio) com telemetria na tela.
3. Atualização de jogos pela rede, direto no launcher.
