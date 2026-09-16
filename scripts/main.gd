extends Node2D

const WORLD := Rect2(70, 100, 1140, 530)
const SAVE_PATH := "user://wraith_save.json"
const PLAYER_SPEED := 175.0
const ATTACK_RANGE := 78.0

var player := {"pos": Vector2(310, 360), "hp": 120, "max_hp": 120, "level": 1, "xp": 0, "next_xp": 70, "gold": 0, "potions": 5, "weapon": 0, "armor": 0, "transformed": false}
var monsters: Array[Dictionary] = []
var bots: Array[Dictionary] = []
var drops: Array[Dictionary] = []
var target: Dictionary = {}
var move_target := Vector2.ZERO
var attack_cooldown := 0.0
var spawn_cooldown := 0.0
var boss_respawn := 0.0
var message := "바닥을 터치해 이동하고, 몬스터를 터치하면 자동 공격합니다."
var message_time := 8.0
var hit_flash := 0.0
var shake := 0.0
var ui: CanvasLayer
var labels := {}

func _ready() -> void:
    get_viewport().set_embedding_subwindows(false)
    _build_ui()
    _spawn_initial_world()
    _load_game()
    queue_redraw()

func _build_ui() -> void:
    ui = CanvasLayer.new()
    add_child(ui)
    var top := ColorRect.new()
    top.color = Color("17191b")
    top.position = Vector2(0, 0)
    top.size = Vector2(1280, 82)
    ui.add_child(top)
    labels["title"] = _label("망령군주  ·  잿빛섬", Vector2(24, 14), 24, Color("e7d5a7"))
    labels["stats"] = _label("", Vector2(24, 46), 17, Color("d6d2c5"))
    labels["target"] = _label("대상 없음", Vector2(760, 20), 18, Color("f0c978"))
    labels["message"] = _label("", Vector2(80, 650), 18, Color("f2e7c9"))
    var hint := _label("이동: 화면 터치  |  공격: 몬스터 터치", Vector2(870, 650), 14, Color("aaa89f"))
    hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    hint.size.x = 330
    _button("물약", Vector2(1070, 100), Vector2(130, 58), _use_potion)
    _button("강화", Vector2(1070, 169), Vector2(130, 58), _upgrade_weapon)
    _button("변신", Vector2(1070, 238), Vector2(130, 58), _toggle_transform)
    _button("저장", Vector2(1070, 307), Vector2(130, 58), _save_game)

func _label(text: String, pos: Vector2, font_size: int, color: Color) -> Label:
    var label := Label.new()
    label.text = text
    label.position = pos
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    label.size = Vector2(700, 34)
    ui.add_child(label)
    return label

func _button(text: String, pos: Vector2, size: Vector2, callback: Callable) -> void:
    var button := Button.new()
    button.text = text
    button.position = pos
    button.size = size
    button.add_theme_font_size_override("font_size", 18)
    button.pressed.connect(callback)
    ui.add_child(button)

func _spawn_initial_world() -> void:
    monsters.clear()
    bots.clear()
    drops.clear()
    var entries := [
        ["슬라임", Vector2(500, 230), 26, 5, Color("657d45")],
        ["고블린", Vector2(690, 250), 38, 7, Color("78905a")],
        ["오크", Vector2(830, 420), 52, 10, Color("65774c")],
        ["해골", Vector2(610, 490), 45, 9, Color("d0c7a8")],
        ["구울", Vector2(940, 305), 62, 12, Color("77755c")]
    ]
    for entry in entries:
        monsters.append(_monster(entry[0], entry[1], entry[2], entry[3], entry[4]))
    monsters.append(_monster("바포메트", Vector2(955, 510), 360, 38, Color("6b2631"), true))
    bots.append(_bot("라온", Vector2(410, 525), Color("668baa"), "사냥꾼"))
    bots.append(_bot("월영", Vector2(760, 560), Color("815d8c"), "호전형"))
    bots.append(_bot("백린", Vector2(875, 190), Color("a27c4e"), "지원형"))

func _monster(name: String, pos: Vector2, hp: int, power: int, color: Color, boss := false) -> Dictionary:
    return {"name": name, "pos": pos, "hp": hp, "max_hp": hp, "power": power, "color": color, "boss": boss, "alive": true, "respawn": 0.0, "flash": 0.0}

func _bot(name: String, pos: Vector2, color: Color, nature: String) -> Dictionary:
    return {"name": name, "pos": pos, "hp": 90, "max_hp": 90, "level": 2, "color": color, "nature": nature, "goal": Vector2.ZERO, "cooldown": randf_range(0.2, 0.8), "target": -1}

func _process(delta: float) -> void:
    attack_cooldown = maxf(0.0, attack_cooldown - delta)
    spawn_cooldown -= delta
    message_time = maxf(0.0, message_time - delta)
    hit_flash = maxf(0.0, hit_flash - delta)
    shake = maxf(0.0, shake - delta * 30.0)
    _move_player(delta)
    _update_player_combat()
    _update_monsters(delta)
    _update_bots(delta)
    _update_drops()
    _update_ui()
    queue_redraw()

func _move_player(delta: float) -> void:
    var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
    if input_dir.length() > 0.1:
        move_target = Vector2.ZERO
        target = {}
        player.pos += input_dir.normalized() * PLAYER_SPEED * delta
    elif move_target != Vector2.ZERO:
        var distance: float = player.pos.distance_to(move_target)
        if distance > 5.0:
            player.pos = player.pos.move_toward(move_target, PLAYER_SPEED * delta)
        else:
            move_target = Vector2.ZERO
    player.pos.x = clampf(player.pos.x, WORLD.position.x + 20, WORLD.end.x - 165)
    player.pos.y = clampf(player.pos.y, WORLD.position.y + 30, WORLD.end.y - 25)

func _update_player_combat() -> void:
    if target.is_empty() or not target.get("alive", false):
        target = {}
        return
    var distance: float = player.pos.distance_to(target.pos)
    if distance > ATTACK_RANGE:
        player.pos = player.pos.move_toward(target.pos, PLAYER_SPEED * get_process_delta_time())
        return
    move_target = Vector2.ZERO
    if attack_cooldown <= 0.0:
        var speed := 0.34 if player.transformed else 0.48
        attack_cooldown = speed
        var damage := randi_range(8, 13) + player.level * 2 + player.weapon * 3
        if randf() < 0.13:
            damage *= 2
            _say("치명타! %d 피해" % damage)
        target.hp -= damage
        target.flash = 0.10
        hit_flash = 0.07
        shake = 5.0
        if target.hp <= 0:
            _monster_defeated(target)

func _monster_defeated(monster: Dictionary) -> void:
    monster.alive = false
    monster.respawn = 28.0 if monster.boss else randf_range(6.0, 11.0)
    var xp_gain: int = monster.power * (4 if monster.boss else 2)
    var gold_gain: int = monster.power * randi_range(2, 4)
    player.xp += xp_gain
    player.gold += gold_gain
    drops.append({"pos": monster.pos + Vector2(16, 8), "name": "강화석" if monster.boss or randf() < 0.25 else "황혼 주화", "life": 14.0})
    _say("%s 처치!  경험치 +%d  주화 +%d" % [monster.name, xp_gain, gold_gain])
    target = {}
    _check_level_up()

func _check_level_up() -> void:
    while player.xp >= player.next_xp:
        player.xp -= player.next_xp
        player.level += 1
        player.next_xp = int(player.next_xp * 1.45)
        player.max_hp += 16
        player.hp = player.max_hp
        _say("레벨 %d 달성! 생명력이 회복되었습니다." % player.level)

func _update_monsters(delta: float) -> void:
    for monster in monsters:
        monster.flash = maxf(0.0, monster.flash - delta)
        if not monster.alive:
            monster.respawn -= delta
            if monster.respawn <= 0.0:
                monster.alive = true
                monster.hp = monster.max_hp
                _say("%s이(가) 다시 출현했습니다." % monster.name)
            continue
        var distance: float = monster.pos.distance_to(player.pos)
        if distance < (105.0 if monster.boss else 70.0) and randf() < delta * 1.5:
            var damage: int = maxi(1, monster.power - player.armor * 2)
            player.hp -= damage
            hit_flash = 0.12
            if player.hp <= 0:
                _player_died()

func _player_died() -> void:
    player.hp = player.max_hp
    player.pos = Vector2(260, 355)
    player.xp = maxi(0, player.xp - int(player.next_xp * 0.05))
    target = {}
    move_target = Vector2.ZERO
    _say("사망했습니다. 잿빛 마을에서 부활하며 경험치가 감소했습니다.")

func _update_bots(delta: float) -> void:
    for bot in bots:
        bot.cooldown = maxf(0.0, bot.cooldown - delta)
        var index: int = bot.target
        if index < 0 or index >= monsters.size() or not monsters[index].alive:
            index = _nearest_monster_index(bot.pos, bot.nature == "지원형")
            bot.target = index
        if index < 0:
            continue
        var enemy: Dictionary = monsters[index]
        var distance: float = bot.pos.distance_to(enemy.pos)
        if distance > 68.0:
            bot.pos = bot.pos.move_toward(enemy.pos, (105.0 + bot.level * 4) * delta)
        elif bot.cooldown <= 0.0:
            bot.cooldown = randf_range(0.55, 0.9)
            enemy.hp -= randi_range(4, 8) + bot.level
            enemy.flash = 0.08
            if enemy.hp <= 0:
                enemy.alive = false
                enemy.respawn = 25.0 if enemy.boss else randf_range(7.0, 12.0)
                bot.level += 1 if randf() < 0.18 else 0
                bot.target = -1
                _say("모험가 %s이(가) %s을(를) 처치했습니다." % [bot.name, enemy.name])

func _nearest_monster_index(origin: Vector2, avoid_boss: bool) -> int:
    var best := -1
    var best_distance := INF
    for i in monsters.size():
        var monster: Dictionary = monsters[i]
        if not monster.alive or (avoid_boss and monster.boss):
            continue
        var distance := origin.distance_squared_to(monster.pos)
        if distance < best_distance:
            best_distance = distance
            best = i
    return best

func _update_drops() -> void:
    var delta := get_process_delta_time()
    for drop in drops:
        drop.life -= delta
        if player.pos.distance_to(drop.pos) < 45.0:
            if drop.name == "강화석":
                player.gold += 35
                _say("강화석을 획득했습니다. 강화 비용으로 환산됩니다.")
            else:
                player.gold += 8
            drop.life = 0.0
    drops = drops.filter(func(drop: Dictionary) -> bool: return drop.life > 0.0)

func _unhandled_input(event: InputEvent) -> void:
    var pressed := false
    var position := Vector2.ZERO
    if event is InputEventScreenTouch and event.pressed:
        pressed = true
        position = event.position
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        pressed = true
        position = event.position
    if not pressed or not WORLD.has_point(position) or position.x > 1045:
        return
    var picked: Dictionary = {}
    var nearest := 58.0
    for monster in monsters:
        if monster.alive:
            var distance: float = position.distance_to(monster.pos)
            if distance < nearest:
                nearest = distance
                picked = monster
    if not picked.is_empty():
        target = picked
        move_target = Vector2.ZERO
        _say("%s을(를) 공격 대상으로 지정했습니다." % picked.name)
    else:
        target = {}
        move_target = position

func _use_potion() -> void:
    if player.potions <= 0:
        _say("물약이 없습니다.")
        return
    if player.hp >= player.max_hp:
        _say("생명력이 이미 가득 찼습니다.")
        return
    player.potions -= 1
    player.hp = mini(player.max_hp, player.hp + 55)
    _say("체력 회복 물약을 사용했습니다.")

func _upgrade_weapon() -> void:
    var cost := 30 + player.weapon * 25
    if player.gold < cost:
        _say("강화에 황혼 주화 %d개가 필요합니다." % cost)
        return
    player.gold -= cost
    var chance := maxf(0.38, 0.92 - player.weapon * 0.09)
    if randf() <= chance:
        player.weapon += 1
        _say("강화 성공! 무기가 +%d이 되었습니다." % player.weapon)
    elif player.weapon > 3:
        player.weapon -= 1
        _say("강화 실패. 무기 강화 수치가 1 감소했습니다.")
    else:
        _say("강화에 실패했지만 장비는 보호되었습니다.")

func _toggle_transform() -> void:
    if player.level < 3:
        _say("데스나이트 변신은 레벨 3부터 사용할 수 있습니다.")
        return
    player.transformed = not player.transformed
    _say("데스나이트로 변신했습니다." if player.transformed else "변신을 해제했습니다.")

func _save_game() -> void:
    var data := {
        "level": player.level, "xp": player.xp, "next_xp": player.next_xp,
        "gold": player.gold, "potions": player.potions, "weapon": player.weapon,
        "armor": player.armor, "max_hp": player.max_hp
    }
    var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(data))
        _say("진행 상황을 휴대폰에 저장했습니다.")

func _load_game() -> void:
    if not FileAccess.file_exists(SAVE_PATH):
        return
    var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
    var data = JSON.parse_string(file.get_as_text())
    if data is Dictionary:
        for key in data:
            if player.has(key):
                player[key] = data[key]
        player.hp = player.max_hp
        _say("저장된 진행 상황을 불러왔습니다.")

func _say(text: String) -> void:
    message = text
    message_time = 4.0

func _update_ui() -> void:
    labels.stats.text = "Lv.%d   HP %d/%d   EXP %d/%d   황혼 주화 %d   물약 %d   무기 +%d" % [player.level, player.hp, player.max_hp, player.xp, player.next_xp, player.gold, player.potions, player.weapon]
    labels.message.text = message if message_time > 0.0 else ""
    if target.is_empty():
        labels.target.text = "대상 없음"
    else:
        labels.target.text = "%s   HP %d/%d" % [target.name, maxi(0, target.hp), target.max_hp]

func _draw() -> void:
    var offset := Vector2(randf_range(-shake, shake), randf_range(-shake, shake)) if shake > 0.0 else Vector2.ZERO
    draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color("0b0e0d"))
    draw_rect(WORLD, Color("2b3028"))
    _draw_world_tiles(offset)
    for drop in drops:
        draw_circle(drop.pos + offset, 8, Color("e3c55b"))
        draw_arc(drop.pos + offset, 13, 0, TAU, 16, Color("fff1a6"), 2)
    for monster in monsters:
        if monster.alive:
            _draw_monster(monster, offset)
    for bot in bots:
        _draw_warrior(bot.pos + offset, bot.color, false, bot.name, bot.hp, bot.max_hp)
    _draw_warrior(player.pos + offset, Color("25292d") if not player.transformed else Color("14131a"), player.transformed, "나", player.hp, player.max_hp)
    if hit_flash > 0.0:
        draw_rect(WORLD, Color(0.7, 0.08, 0.05, hit_flash * 0.8))

func _draw_world_tiles(offset: Vector2) -> void:
    for x in range(90, 1040, 64):
        for y in range(120, 620, 38):
            var tone := Color("34392f") if int(x / 64.0 + y / 38.0) % 2 == 0 else Color("30352c")
            draw_colored_polygon(PackedVector2Array([Vector2(x, y)+offset, Vector2(x+32, y-18)+offset, Vector2(x+64, y)+offset, Vector2(x+32, y+18)+offset]), tone)
    draw_rect(Rect2(100, 285, 245, 180), Color("5c5546"), false, 6)
    draw_string(ThemeDB.fallback_font, Vector2(125, 315), "잿빛 마을 · 안전지대", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("c7b990"))
    for p in [Vector2(160,170), Vector2(270,560), Vector2(470,570), Vector2(1010,155), Vector2(1020,580)]:
        draw_circle(p + offset, 28, Color("1c241b"))
        draw_circle(p + offset + Vector2(0,-18), 22, Color("33402d"))

func _draw_warrior(pos: Vector2, color: Color, death_knight: bool, name: String, hp: int, max_hp: int) -> void:
    draw_ellipse(pos + Vector2(0, 23), Vector2(24, 9), Color(0,0,0,0.45))
    var body := Color("19191d") if death_knight else color
    draw_rect(Rect2(pos + Vector2(-15,-16), Vector2(30,38)), body)
    draw_colored_polygon(PackedVector2Array([pos+Vector2(-25,-12),pos+Vector2(-13,-24),pos+Vector2(-8,-5)]), Color("3d4145") if not death_knight else Color("54232b"))
    draw_colored_polygon(PackedVector2Array([pos+Vector2(25,-12),pos+Vector2(13,-24),pos+Vector2(8,-5)]), Color("3d4145") if not death_knight else Color("54232b"))
    draw_circle(pos + Vector2(0,-27), 13, Color("c9b48d") if not death_knight else Color("d8d0b2"))
    draw_rect(Rect2(pos + Vector2(-13,-33), Vector2(26,9)), Color("34383c") if not death_knight else Color("17161b"))
    draw_circle(pos + Vector2(-5,-27), 2.5, Color("202020") if not death_knight else Color("60d6ff"))
    draw_circle(pos + Vector2(5,-27), 2.5, Color("202020") if not death_knight else Color("60d6ff"))
    var swing := 18.0 if attack_cooldown > 0.32 and name == "나" else 0.0
    draw_line(pos + Vector2(13,-5), pos + Vector2(36,-28+swing), Color("b7bcc0") if not death_knight else Color("90d9e8"), 6)
    draw_line(pos + Vector2(36,-28+swing), pos + Vector2(48,-38+swing), Color("edf5f5"), 3)
    _draw_health_bar(pos + Vector2(-27,-52), hp, max_hp, 54)
    draw_string(ThemeDB.fallback_font, pos + Vector2(-25,-59), name, HORIZONTAL_ALIGNMENT_CENTER, 50, 13, Color("eeeeeb"))

func _draw_monster(monster: Dictionary, offset: Vector2) -> void:
    var pos: Vector2 = monster.pos + offset
    var color: Color = Color.WHITE if monster.flash > 0.0 else monster.color
    draw_ellipse(pos + Vector2(0, 19), Vector2(25 if monster.boss else 18, 8), Color(0,0,0,0.45))
    if monster.boss:
        draw_colored_polygon(PackedVector2Array([pos+Vector2(-34,20),pos+Vector2(-27,-30),pos+Vector2(0,-48),pos+Vector2(27,-30),pos+Vector2(34,20)]), color)
        draw_line(pos+Vector2(-17,-36), pos+Vector2(-34,-58), Color("d7c7a2"), 7)
        draw_line(pos+Vector2(17,-36), pos+Vector2(34,-58), Color("d7c7a2"), 7)
        draw_circle(pos+Vector2(0,-33), 15, Color("2a191b"))
        draw_circle(pos+Vector2(-6,-34), 3, Color("ff643f"))
        draw_circle(pos+Vector2(6,-34), 3, Color("ff643f"))
    elif monster.name == "슬라임":
        draw_circle(pos, 19, color)
        draw_rect(Rect2(pos+Vector2(-19,0), Vector2(38,18)), color)
    elif monster.name == "해골":
        draw_circle(pos+Vector2(0,-18), 12, color)
        draw_line(pos+Vector2(0,-6), pos+Vector2(0,18), color, 7)
        draw_line(pos+Vector2(-14,4), pos+Vector2(14,4), color, 5)
    else:
        draw_circle(pos+Vector2(0,-17), 12, color)
        draw_rect(Rect2(pos+Vector2(-14,-6), Vector2(28,29)), color)
    _draw_health_bar(pos + Vector2(-28,-48 if monster.boss else -39), monster.hp, monster.max_hp, 56)
    draw_string(ThemeDB.fallback_font, pos + Vector2(-35,-54 if monster.boss else -45), monster.name, HORIZONTAL_ALIGNMENT_CENTER, 70, 13, Color("f2dfc5"))
    if not target.is_empty() and target == monster:
        draw_arc(pos, 38 if monster.boss else 29, 0, TAU, 32, Color("f4cf67"), 3)

func _draw_health_bar(pos: Vector2, hp: int, max_hp: int, width: float) -> void:
    draw_rect(Rect2(pos, Vector2(width, 5)), Color("211d1d"))
    draw_rect(Rect2(pos, Vector2(width * clampf(float(hp) / float(max_hp), 0.0, 1.0), 5)), Color("a8433c"))

func draw_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
    var points := PackedVector2Array()
    for i in 24:
        var angle := TAU * i / 24.0
        points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
    draw_colored_polygon(points, color)
