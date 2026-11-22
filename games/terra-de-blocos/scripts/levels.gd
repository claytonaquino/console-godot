class_name Levels
extends RefCounted
## Mapas (cada caractere é um quadrado de 2 x 2 m) e falas da história.
##
## Legenda: . grama  , trilha  # muro  T árvore  P pinheiro  r ruína  R pedra
##   ~ água  f flores  b arbusto  H casa  S início  X saída  G portão  L alavanca
##   B parede quebrável  C baú  A artefato  c moeda  i placa  e rastejante
##   a emboscada  K chefe  1-4 pontos de reforço  M quadro de missões
##   O oficina  N morador

const MAPS := {
	"m1": [
		"####################################",
		"#PPTP...r...r.......r....r...TPPPPP#",
		"#P....a....r...r.A.r...a..r......TP#",
		"#T..r....r.........r.......r...r..P#",
		"#P..........a....c.....a.........TP#",
		"#TP...r........r.....r.......r..PPP#",
		"#PPT............................TPP#",
		"#################GG#################",
		"#PPTP.........,,,,,,,,,.......PPTPP#",
		"#P...b....L...,.......,...L.....bTP#",
		"#T....i.......,...e...,.........b.P#",
		"#PT..........,,...c...,,..........T#",
		"#P....b......,..........,....####P.#",
		"#TP.........,....e...e...,...#C.#..#",
		"#P..T.......,............,...#c.B..#",
		"#PT...b.....,,..........,,...####..#",
		"#P...........,,,,,,,,,,,,.......bPT#",
		"#TP..f...........,..............f.P#",
		"#P...b...T.......,.....T....b.....T#",
		"#PT..........f..,i...........f...PP#",
		"#P..T...........,,..........T.....T#",
		"#PPT......f......,.....f.......PPPP#",
		"#PPTT............S.X.............TP#",
		"####################################",
	],
	"m2": [
		"##################################",
		"#PPTPP...........1........PPTPPTP#",
		"#P...H.....f..........f.....H..TP#",
		"#T.......b.......K.........b....P#",
		"#P..f.........................f.T#",
		"#2.....H....f.........f....H....3#",
		"#P.........,,,,,,,,,,,,.........P#",
		"#T....b....,..........,....b....T#",
		"#P.........,...ffff...,.........P#",
		"#TP..H.....,...f..f...,.....H..PT#",
		"#P.........,...ffff...,.........P#",
		"#T....f....,..........,....f....T#",
		"#P.........,,,,,,,,,,,,.........P#",
		"#TP....H.......,..,.......H.....P#",
		"#P...b.........,S.,........b....T#",
		"#PT..f...H.....,,,,....H....f..PP#",
		"#PPTPP...........4.........PPTPPT#",
		"##################################",
	],
	"vila": [
		"##############################",
		"#PPTPPTP....~~~~~.....PTPPTPP#",
		"#P..H......~~~~~~~.....H...TP#",
		"#T.......f..~~~~~...f.......P#",
		"#P...N.......,,,..........H.T#",
		"#TP..........,M,.....O......P#",
		"#P...H.......,,,....,,,..f..T#",
		"#T.....f.......,,,,,,.......P#",
		"#P.......,,,,,,,S,,,,,,,..N.T#",
		"#TP..H...,.....,......,..H..P#",
		"#P....f..,..b..,..b...,.....T#",
		"#PPT.....,,,,,,X,,,,,,,..PPTP#",
		"##############################",
	],
}

const MISSIONS := [
	{"id": "m1", "title": "O Chamado", "desc": "Atravesse a floresta, abra o portão das ruínas e descubra o que está piscando lá dentro."},
	{"id": "m2", "title": "Ataque à Vila", "desc": "Máquinas cercam a vila! Aguente as ondas e enfrente o Colosso de Sucata."},
]

const TALK := {
	"m1_start": [
		["Iara", "Mais um dia de caça... e mais um dia de todo mundo da vila me olhando torto."],
		["Bento", "Iara! A anciã Zuza mandou buscar uma coisa nas ruínas do norte. Disse que é URGENTE."],
		["Bento", "Ou que esqueceu o bolo no forno. Não entendi direito."],
		["Iara", "Então vamos pela floresta. E fica atento: tem máquina estranha por lá."],
	],
	"m1_sign1": [["Placa", "Analógico anda. X (ou J) ataca. A (ou Espaço) faz rolamento. LB (ou Tab) troca de herói."]],
	"m1_sign2": [["Placa", "Mire nas peças BRILHANTES das máquinas: dano crítico e elas caem!"]],
	"m1_levers": [["Bento", "Duas alavancas... uma de cada lado. Acerte as duas para abrir o portão."]],
	"m1_gate": [["Iara", "Abriu! As ruínas estão logo ali."]],
	"m1_secret": [["Bento", "Ei, esse muro parece rachado. Será que esconde alguma coisa?"]],
	"m1_artifact": [
		["Iara", "Que cubo é esse? Está... piscando pra mim?"],
		["Artefato", "OLÁ, USUÁRIA. BATERIA EM 3%. FAVOR NÃO ME DEIXAR CAIR."],
		["Bento", "O cubo fala! Eu não vou carregar isso."],
		["NÚCLEO-0", "Sinal detectado. Enviando unidades de coleta."],
		["Iara", "Isso não soou nada bem. Prepare a lança!"],
	],
	"m1_exit": [["Artefato", "ROTA PARA CASA CALCULADA: SAÍDA AO SUL. DE NADA."]],
	"m1_end": [
		["Bento", "Chegamos! E eu nem perdi o capacete."],
		["Artefato", "ALERTA: NÚCLEO-0 DESPERTOU. ELE QUER CONTROLAR TODAS AS MÁQUINAS DO MUNDO."],
		["Iara", "Então alguém vai ter que desligar esse tal de NÚCLEO-0."],
		["Bento", "Alguém tipo... nós?"],
	],
	"m2_start": [
		["Zuza", "Máquinas atacando a vila! Protejam as casas! E minhas abóboras!"],
		["Bento", "Deixa com a gente, dona Zuza!"],
	],
	"m2_boss": [
		["NÚCLEO-0", "Contemplem: o COLOSSO DE SUCATA!"],
		["Bento", "Ele foi montado com peças de máquina de lavar?"],
		["Iara", "Mira nas peças que brilham: primeiro os mísseis, depois os canhões!"],
	],
	"m2_end": [
		["Bento", "Ele desmontou igualzinho à minha estante."],
		["Zuza", "Muito bem! As abóboras estão salvas. Quer dizer... a vila também."],
		["Artefato", "PARABÉNS. CAPÍTULO 1 CONCLUÍDO. PRÓXIMA PARADA: AS RUÍNAS PERDIDAS."],
		["Iara", "Quem é que fica falando em \"capítulo\"?"],
	],
}

const NPC_LINES := [
	["Zuza", "Explosivos não são brinquedo. A não ser que sejam feitos de bloco."],
	["Tico", "Dizem que as máquinas antigas sonhavam com peças de reposição."],
	["Zuza", "Gaste suas moedas na Oficina. Um herói de coração cheio luta melhor!"],
	["Tico", "Eu tentei montar uma máquina uma vez. Virou uma cadeira."],
	["Zuza", "Quando os blocos caem, o mundo se monta de novo. Ditado antigo."],
]
