class_name Tire
extends RefCounted
## Modelo de pneu: "fórmula mágica" de Pacejka (versão simplificada),
## com escorregamento combinado pelo vetor de escorregamento.
##
##   F = D · sin(C · atan(B·s − E·(B·s − atan(B·s))))
##
## s  = escorregamento (longitudinal κ ou tan α lateral)
## D  = μ · Fz (pico), B = rigidez, C = forma, E = curvatura.

# Coeficientes típicos de pneu de rua (pico perto de κ ≈ 0,10 e α ≈ 7°).
const BX := 12.0
const CX := 1.65
const EX := 0.10
const BY := 9.0
const CY := 1.35
const EY := -0.60
## Carga nominal usada na sensibilidade à carga (N).
const FZ_NOMINAL := 3000.0
## Quanto o μ cai por unidade de carga acima da nominal.
const LOAD_SENSITIVITY := 0.08


static func magic(s: float, b: float, c: float, e: float) -> float:
	var bs := b * s
	return sin(c * atan(bs - e * (bs - atan(bs))))


## Retorna Vector2(Fx, Fy_bruto) para o escorregamento combinado.
## kappa: escorregamento longitudinal; tan_alpha: tangente do ângulo de deriva.
## O sinal de Fy segue tan_alpha (quem chama inverte para opor a deriva).
static func forces(kappa: float, tan_alpha: float, fz: float, mu: float) -> Vector2:
	if fz <= 0.0:
		return Vector2.ZERO
	var mu_eff := mu * maxf(0.6, 1.0 - LOAD_SENSITIVITY * (fz / FZ_NOMINAL - 1.0))
	var d := mu_eff * fz
	var sigma := sqrt(kappa * kappa + tan_alpha * tan_alpha)
	if sigma < 1e-6:
		return Vector2.ZERO
	var fx0 := d * magic(sigma, BX, CX, EX)
	var fy0 := d * magic(sigma, BY, CY, EY)
	return Vector2(fx0 * kappa / sigma, fy0 * tan_alpha / sigma)
