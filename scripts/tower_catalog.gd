class_name TowerCatalog
extends Control

func _draw() -> void:
	var width:=size.x/4
	var height:=size.y/4
	for row in 4:
		var kind: String=Balance.KINDS[row]
		draw_string(ThemeDB.fallback_font,Vector2(4,row*height+24),Balance.tower(kind).name,HORIZONTAL_ALIGNMENT_LEFT,-1,19,Color(Balance.tower(kind).color))
		for col in 4:
			var pos:=Vector2(width*(col+.5),height*(row+.55))
			TowerVisuals.draw(self,pos,kind,34,[1,5,10,10][col],col==3,col==3)
			draw_string(ThemeDB.fallback_font,pos+Vector2(-15,56),["1","5","10","MEGA"][col],HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("cad8e1"))
