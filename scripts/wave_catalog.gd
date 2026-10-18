class_name WaveCatalog
extends RefCounted

static func rounded(value: float) -> int:
	return int(floor(value+.5))

static func generate(w: int) -> Dictionary:
	Balance.load_config()
	var f: Dictionary=Balance.cfg.wave_formula
	var x:=float(mini(w,100)-1)
	var endless:=pow(f.endless_growth,maxi(0,w-100))
	var late:=maxf(0,x-f.late_start)
	var h:=rounded(f.base_hp*(1+f.hp_linear*x+f.hp_quadratic*x*x+f.hp_cubic*x*x*x)*pow(f.hp_growth,x)*exp(-f.late_softening*late*late)*endless)
	var boss_factor: float=f.boss_hp+f.boss_early_bonus*exp(-x/f.boss_bonus_decay)
	var reward:=maxi(2,rounded(f.reward_base*pow(f.reward_growth,w-1)))
	var count:=mini(30,7+w)
	var groups: Dictionary={}
	if w%20==19: groups={"normal":10,"fast":10,"split":10}
	elif w%5==0: groups={"normal":count,"boss":1}
	else: groups[["normal","fast","split"][(w-1)%3]]=count
	return {"wave":w,"groups":groups,"hp":{"normal":h,"fast":rounded(f.triangle_hp*h),"split":rounded(f.parent_hp*h),"child":rounded(f.child_hp*h),"boss":rounded(boss_factor*h)},
		"reward":{"normal":reward,"fast":reward,"split":rounded(f.parent_reward*reward),"child":maxi(1,rounded(f.child_reward*reward)),"boss":polynomial(f.boss_reward,w)},"completion_bonus":polynomial(f.completion_bonus,w)}

static func polynomial(f: Array, w: int) -> int:
	return rounded(f[0]+f[1]*w+f[2]*w*w)

static func queue(config: Dictionary) -> Array:
	var result: Array=[]
	# Interleave the three types evenly on mixed waves; all initial intervals are equal.
	var remaining: Dictionary=config.groups.duplicate()
	while int(remaining.get("normal",0))+int(remaining.get("fast",0))+int(remaining.get("split",0))>0:
		for kind in ["normal","fast","split"]:
			if int(remaining.get(kind,0))>0:
				result.append(kind); remaining[kind]-=1
	if config.groups.has("boss"): result.append("boss")
	return result
