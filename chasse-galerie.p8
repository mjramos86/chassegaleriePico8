pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
-- chasse-galerie shmup
-- sprites:
-- 001: canoe
-- 002: demon 
-- 003: bullet
-- 005-006, 021-022, 037-038: steeple
-- 010: beer
-- 025: maple

-- constants for gameplay
local demon_meter_fill = 25    -- 25% fill for demons
local steeple_meter_fill = 75  -- 75% fill for steeples

-- game states and global variables
local game_state="title"
local score=0
local high_score=0
local devil_meter=0
local max_devil_meter=100
local snow_particles={}
local enemy_spawn_timer=0
local steeple_spawn_timer=0
local current_level=1
local points_per_level=1000
local narrative_state="none"
local game_start_time = 0
local total_elapsed_time = 0
local midgame_time = 60
local endgame_time = 180
local canoe_invincible = false
local canoe_invincible_timer = 0
local pause_timer = 0
local church_exploding = false
local red_cross = nil  -- will store the cross position when needed
-- ajout des variables pour les meilleurs scores
local high_scores = {}
local max_high_scores = 5
local input_name = ""
local input_state = "none"
local cursor_blink = 0
local max_name_length = 6
local showed_high_scores = false
local current_letter = 1  -- current position in alphabet
local letter_select_timer = 0
local letter_scroll_delay = 6  -- controls scroll speed
local alphabet = "abcdefghijklmnopqrstuvwxyz"

-- modification du get_game_speed pour inclure le score
local function get_game_speed()
    -- base speed + score bonus (accelerates every 1000 points)
    local score_bonus = score / 1000 * 0.1
    return 1.0 + score_bonus + (current_level - 1) * 0.2
end

local function get_spawn_rate()
 return max(10, 30 - (current_level - 1) * 2)  -- decreases spawn delay
end

-- player (canoe) variables
local canoe={
 x=60,
 y=60,
 dx=0,
 dy=0,
 sprite=1,
 health=3,
 controls_reversed=false,
 reverse_timer=0,
 shoot_cooldown=0 
}

local narratives = {
    start = {
        "les gars du camp ont fait",
        "un pacte avec le yable pour",
        "aller veiller avec les",
        "belles filles au village.",
        "si y touchent une eglise",
        "ou disent l'nom du bon dieu,",
        "le yable va avoir leurs ames!",
        "",
        "appuye sur 🅾️ pour commencer"
    },
    midgame = {
        "tabarnak!",
        "les gars sont rendus!",
        "y dansent pis boivent",
        "avec les filles",
        "toute la soiree!",
        "",
        "asteur faut r'tourner",
        "au camp...",
        "le yable va etre",
        "plus mechant!",
        "",
        "appuye sur 🅾️ pour continuer"
    },
    victory = {
        "bapteme!",
        "les bucherons ont reussi",
        "a r'venir au camp",
        "avant le soleil!",
        "",
        "le yable a pas eu",
        "leurs ames a soir,", 
        "mais y'est crissement",
        "pas content...",
        "",
        "appuye sur 🅾️ pour r'commencer"
},
    credits = {
        "",
        "design",
        "mario j. ramos",
        "",
        "code avec assistant ia",
        "claude ai",
        "",
        "merci special a",
        "palass games",
        "",
        "appuye sur 🅾️ pour r'commencer"
    }
}

-- arrays for game objects
local bullets={}
local enemies={}
local particles={}
local powerups={}

-- powerup types
local powerup_types={
 "maple",     -- resets demon meter
 "beer"       -- reverses controls
}

cartdata("chasse_galerie_v1")

function _init()
    showed_high_scores = false  -- explicitly initialize here
    load_high_scores()
    -- initialize snow particles
    for i=1,50 do
        add(snow_particles,{
            x=rnd(128),
            y=rnd(128),
            speed=0.5+rnd(1)
        })
    end
    game_state = "title"  -- make sure it starts in title state
    music(0)
end

function init_game()
    score = 0
    devil_meter = 0
    current_level = 1
    enemy_spawn_timer = 0
    steeple_spawn_timer = 0
    canoe.health = 3
    canoe.x = 60
    canoe.y = 60
    canoe.controls_reversed = false
    canoe.dx = 0
    canoe.dy = 0
    enemies = {}
    bullets = {}
    particles = {}
    powerups = {}
    canoe.shoot_cooldown = 0
    canoe_invincible = false
    canoe_invincible_timer = 0
    pause_timer = 0
    church_exploding = false
    red_cross = nil
    total_elapsed_time = 0
    
    if game_state == "game" then
        narrative_state = "start"
        game_state = "narrative"
    end
end

function blink()
    return flr(time()*2)%2==0 and 7 or 1
end

function load_high_scores()
    local scores = {}
    for i=0,max_high_scores-1 do
        local name = ""
        local score = 0
        
        -- read the name (6 characters max)
        for j=0,5 do
            local char = peek(0x5e00 + i*8 + j)
            if char != 0 then
                name = name..chr(char)
            end
        end
        
        -- read the score (2 bytes for larger numbers)
        score = peek2(0x5e06 + i*8)
        
        if score > 0 then
            add(scores, {name=name, score=score})
        end
    end
    high_scores = scores
end

function save_high_scores()
    -- clear the entire high score storage area first
    for i=0,max_high_scores*8-1 do
        poke(0x5e00 + i, 0)
    end
    
    -- now save the current high scores
    for i=1,#high_scores do
        local score = high_scores[i]
        local base_addr = 0x5e00 + (i-1)*8
        
        -- save name (up to 6 characters)
        for j=1,6 do
            local char = sub(score.name,j,j)
            if char != "" then
                poke(base_addr + j - 1, ord(char))
            end
        end
        
        -- save score value (2 bytes)
        poke2(base_addr + 6, score.score)
    end
end

function insert_high_score(name, score)
    add(high_scores, {name=name, score=score})
    
    -- sort high scores (highest to lowest)
    for i=1,#high_scores do
        for j=i+1,#high_scores do
            if high_scores[i].score < high_scores[j].score then
                high_scores[i],high_scores[j] = high_scores[j],high_scores[i]
            end
        end
    end
    
    -- trim to max size
    while #high_scores > max_high_scores do
        deli(high_scores, #high_scores)
    end
    
    -- save to persistent storage
    save_high_scores()
end

function add_high_score(new_score)
    -- if we have less than max scores, any score qualifies
    if #high_scores < max_high_scores then
        return true
    end
    
    -- get the lowest score from the sorted list
    local lowest_score = high_scores[#high_scores].score
    
    -- check if new score beats the lowest score
    return new_score > lowest_score
end

function spawn_enemy(is_steeple)
 local enemy={}
 if is_steeple then
  -- steeples still only come from top
  enemy={
   x=rnd(112),
   y=-8,
   dx=0,
   dy=0.5,
   sprite=5
  }
 else
  -- demons can come from any edge
  local side=flr(rnd(4))
  if side==0 then -- top
   enemy={
    x=rnd(128),
    y=-8,
    dx=0,
    dy=0.5,
    sprite=2
   }
  elseif side==1 then -- right
   enemy={
    x=128+8,
    y=rnd(128),
    dx=-0.5,
    dy=0,
    sprite=2
   }
  elseif side==2 then -- bottom
   enemy={
    x=rnd(128),
    y=128+8,
    dx=0,
    dy=-0.5,
    sprite=2
   }
  else -- left
   enemy={
    x=-8,
    y=rnd(128),
    dx=0.5,
    dy=0,
    sprite=2
   }
  end
 end
 add(enemies,enemy)
end

function spawn_powerup()
 local powerup_type=powerup_types[flr(rnd(#powerup_types))+1]
 local powerup={
  x=rnd(112)+8,
  y=-8,
  type=powerup_type,
  sprite=powerup_type=="maple" and 25 or 10,  -- 25 for maple, 10 for beer
  dy=0.5
 }
 add(powerups,powerup)
end

function apply_powerup(type, x, y)
 if type=="maple" then
  -- reset demon meter and add points
  devil_meter=0
  score += 500
  -- add visual feedback for points
  add(particles,{
   x=x,
   y=y,
   dy=-0.5,
   dx=0,
   score=true,
   text="+500",
   life=30
  })
 elseif type=="beer" then
  -- reverse controls and subtract points
  canoe.controls_reversed=true
  canoe.reverse_timer=300
  score = max(0, score - 500)  -- prevent negative score
  -- add visual feedback for points lost
  add(particles,{
   x=x,
   y=y,
   dy=-0.5,
   dx=0,
   score=true,
   text="-500",
   life=30
  })
 end
end

function update_game()
    if pause_timer > 0 then
        pause_timer -= 1
        if pause_timer == 0 and church_exploding then
            -- when pause is done, transition to game over
            church_exploding = false
            red_cross = nil
            game_state = "gameover"
            if score > high_score then
                high_score = score
            end
            if score > 0 and add_high_score(score) then
                input_state = "pending"
            else
                input_state = "none"
            end
        end
        return
    end
    
    -- rest of update_game() code...
    total_elapsed_time += 1/60
    
    if flr(total_elapsed_time) == midgame_time then
        narrative_state = "midgame"
        game_state = "narrative"
        return
    elseif flr(total_elapsed_time) == endgame_time then
        narrative_state = "victory"
        game_state = "narrative"
        return
    end
 
    if canoe_invincible then
        canoe_invincible_timer -= 1
        if canoe_invincible_timer <= 0 then
            canoe_invincible = false
        end
    end
    
    update_player()
    update_bullets()
    update_enemies()
    update_particles()
    update_powerups()
    update_spawners()
    update_devil_meter()
    
    if rnd(1)<0.002 then
        spawn_powerup()
    end
    
    check_collisions()
end
function update_spawners()
 local spawn_delay = get_spawn_rate()
 
 -- demon spawning
 enemy_spawn_timer+=1
 if enemy_spawn_timer>spawn_delay and #enemies<8 then
  spawn_enemy(false)
  enemy_spawn_timer=0
 end
 
 -- steeple spawning (less frequent)
 steeple_spawn_timer+=1
 if steeple_spawn_timer>180 and rnd(1)<0.3 then
  spawn_enemy(true)
  steeple_spawn_timer=0
 end
end

function update_player()
    -- update control reversal timer
    if canoe.controls_reversed then
        canoe.reverse_timer-=1
        if canoe.reverse_timer<=0 then
            canoe.controls_reversed=false
        end
    end

    -- movement (using correct pico-8 button numbers)
    local move_speed=2
    canoe.dx=0
    canoe.dy=0
    
    -- handle movement with standard pico-8 directions
    if btn(0) then  -- left
        canoe.dx=canoe.controls_reversed and move_speed or -move_speed
    end
    if btn(1) then  -- right
        canoe.dx=canoe.controls_reversed and -move_speed or move_speed
    end
    if btn(2) then  -- up
        canoe.dy=canoe.controls_reversed and move_speed or -move_speed
    end
    if btn(3) then  -- down
        canoe.dy=canoe.controls_reversed and -move_speed or move_speed
    end
    
    -- update canoe position with bounds checking
    canoe.x+=canoe.dx
    canoe.y+=canoe.dy
    canoe.x=mid(0,canoe.x,120)
    canoe.y=mid(0,canoe.y,120)
    
    -- shooting controls
    if canoe.shoot_cooldown > 0 then
        canoe.shoot_cooldown -= 1
    end
    
    -- o button (4) shoots left, x button (5) shoots right
    if (btn(5) or btn(4)) and canoe.shoot_cooldown <= 0 then
        if btn(5) then       -- o button (shoot left)
            add_bullet(-1, 0)
        else                 -- x button (shoot right)
            add_bullet(1, 0)
        end
        sfx(0)
        canoe.shoot_cooldown = 20  -- add delay between shots
    end
end

function draw_narrative()
    cls()
    draw_snow()
    local text = narratives[narrative_state]
    local y = 35
    
    -- draw appropriate sprite based on narrative state
    if narrative_state == "start" then
        -- draw 4x4 lumberjack portrait
        local base_x = 40  -- centered position
        local base_y = 5   -- above text
        -- draw 4x4 grid of sprites
        spr(68, base_x, base_y, 4, 4)     -- 4,4 means 4 sprites wide, 4 sprites tall
    elseif narrative_state == "midgame" then
        -- draw 4x4 festive image
        local base_x = 40
        local base_y = 5
        spr(74, base_x, base_y, 4, 4)
    elseif narrative_state == "victory" then
        -- draw 4x4 rising sun
        local base_x = 40
        local base_y = 5
        spr(133, base_x, base_y, 4, 4)
    end
    
    -- center each line with more space
    for i,line in ipairs(text) do
        -- calculate center position but ensure minimum margin
        local x = max(4, 64 - (#line * 2))
        print(line, x, y + i*8, 7)
    end
end

function update_narrative()
    if btnp(🅾️) then
        if narrative_state == "victory" then
            if score > 0 and add_high_score(score) then
                -- set up for high score input
                input_state = "highscore"
                input_name = ""
                current_letter = 1
                cursor_blink = 0
                game_state = "gameover"
            else
                narrative_state = "credits"
            end
        elseif narrative_state == "credits" then
            game_state = "title"
            init_game()
        elseif narrative_state == "start" then
            game_state = "game"
            total_elapsed_time = 0
            canoe.shoot_cooldown = 30
        elseif narrative_state == "midgame" then
            game_state = "game"
            total_elapsed_time = midgame_time + 1
            canoe.shoot_cooldown = 30
        end
    end
end


function split(str, separator)
    local parts = {}
    for part in str:gmatch("[^"..separator.."]+") do
        add(parts, part)
    end
    return parts
end

function update_devil_meter()
 -- decrease devil meter over time
 devil_meter=max(0,devil_meter-0.05)
 
 -- check if meter is full (greater than or equal to max)
 if devil_meter >= max_devil_meter then
  game_over("the devil claims your soul!")
 end
end

function add_bullet(dx, dy)
 local bullet_speed = 4
 local bullet={
  x=canoe.x+4,
  y=canoe.y+4,
  dx=dx*bullet_speed,
  dy=dy*bullet_speed,
  sprite=3
 }
 add(bullets,bullet)
end
function check_collisions()
    -- bullet hits enemy section
    for b in all(bullets) do
        for e in all(enemies) do
            if collision(b,e) then
                if e.sprite == 5 then
                    -- set the red cross at the church position
                    red_cross = {
                        x = e.x,
                        y = e.y
                    }
                    -- set up pause and game over sequence
                    pause_timer = 60  -- 1 second pause
                    church_exploding = true
                    game_over_reason = {
                        "crisse!",
                        "lance pas tes prieres",
                        "sur les eglises!"
                    }
                    -- remove bullet but keep church until pause is done
                    del(bullets, b)
                    return
                end
                
                -- regular enemy hit
                del(bullets,b)
                if e.sprite == 2 then
                    score += 100
                    add(particles,{
                        x=e.x,
                        y=e.y,
                        dy=-0.5,
                        dx=0,
                        score=true,
                        text="+100",
                        life=30
                    })
                end
                del(enemies,e)
                create_explosion(e.x,e.y)
                break
            end
        end
    end

    -- enemy hits player
    for e in all(enemies) do
        if collision(canoe,e) and not canoe_invincible then
            if e.sprite == 5 then
                -- set the red cross at the church position
                red_cross = {
                    x = e.x,
                    y = e.y
                }
                -- set up pause and game over sequence
                pause_timer = 60
                church_exploding = true
                game_over_reason = {
                    "calisse!",
                    "fonce pas sur les",
                    "eglises!"
                }
                return
            end
            
            -- regular enemy collision
            canoe_invincible = true
            canoe_invincible_timer = 120
            score = max(0, score - 20)
            add(particles,{
                x=canoe.x,
                y=canoe.y,
                dy=-0.5,
                dx=0,
                score=true,
                text="-20",
                life=30
            })
            devil_meter = min(max_devil_meter, devil_meter + demon_meter_fill)
            create_explosion(e.x,e.y)
            del(enemies,e)

            if devil_meter >= max_devil_meter then
                game_over("evite les demons",
                         "sinon le yable",
                         "prend ton ame!")
            end
        end
    end
    
    -- powerup collisions
    for p in all(powerups) do
        if collision(canoe,p) then
            apply_powerup(p.type, p.x, p.y)
            del(powerups,p)
        end
    end
end
function create_large_explosion(x,y)
    -- create multiple explosion points for the church
    local points = {
        {x=x, y=y},         -- top-left
        {x=x+16, y=y},      -- top-right
        {x=x, y=y+12},      -- middle-left
        {x=x+16, y=y+12},   -- middle-right
        {x=x, y=y+24},      -- bottom-left
        {x=x+16, y=y+24},   -- bottom-right
    }
    
    -- create particles from each point
    for p in all(points) do
        for i=1,8 do
            add(particles,{
                x=p.x,
                y=p.y,
                dx=cos(i/8)*2.5,
                dy=sin(i/8)*2.5,
                life=30,
                size=2  -- larger particles
            })
        end
    end
    
    -- add some debris particles
    for i=1,12 do
        add(particles,{
            x=x+8,
            y=y+12,
            dx=cos(i/12)*4,
            dy=sin(i/12)*4,
            life=45,
            size=3  -- even larger debris
        })
    end
    sfx(1)
end

function collision(a,b)
    -- set default collision boxes
    local a_width=8
    local a_height=8
    local b_width=8
    local b_height=8
    
    -- special case for steeples
    if b.sprite == 5 then
        b_width=14
        b_height=22
        -- calculate exact center of steeple
        local steeple_center_x = b.x + 8  -- half of 16 (sprite width)
        local steeple_center_y = b.y + 12  -- half of 24 (sprite height)
        -- calculate corners of collision box exactly
        return (abs((a.x + a_width/2) - steeple_center_x) < b_width/2) and
               (abs((a.y + a_height/2) - steeple_center_y) < b_height/2)
    end
    
    return abs(a.x - b.x) < (a_width + b_width)/2 and
           abs(a.y - b.y) < (a_height + b_height)/2
end
function create_explosion(x,y)
 for i=1,8 do
  add(particles,{
   x=x,
   y=y,
   dx=cos(i/8)*2,
   dy=sin(i/8)*2,
   life=20
  })
 end
 sfx(1)
end

function update_snow()
 for s in all(snow_particles) do
  s.y+=s.speed*get_game_speed()
  if s.y>128 then
   s.y=0
   s.x=rnd(128)
  end
 end
end

function update_enemies()
 local speed = get_game_speed()
 for e in all(enemies) do
  e.x+=e.dx*speed
  e.y+=e.dy*speed
  -- remove if off screen
  if e.x<-8 or e.x>128+8 or
     e.y<-8 or e.y>128+8 then
   del(enemies,e)
  end
 end
end

function update_bullets()
 for b in all(bullets) do
  b.x+=b.dx
  b.y+=b.dy
  -- remove if off screen
  if b.x<-8 or b.x>128+8 or
     b.y<-8 or b.y>128+8 then
   del(bullets,b)
  end
 end
end

function update_powerups()
 for p in all(powerups) do
  p.y+=p.dy*get_game_speed()
  if p.y>128 then
   del(powerups,p)
  end
 end
end

function update_particles()
    for p in all(particles) do
        -- move particle if it has movement values
        if p.dx then p.x += p.dx end
        if p.dy then p.y += p.dy end
        -- decrease lifetime
        p.life -= 1
        -- remove if lifetime is over
        if p.life <= 0 then
            del(particles,p)
        end
    end
end
function _update60()
    if game_state=="game" then
        update_game()
        update_snow()
    elseif game_state=="title" then
        update_title()
        update_snow()
    elseif game_state=="narrative" then
        update_narrative()
        update_snow()
    elseif game_state=="gameover" then
        update_gameover()
        update_snow()
    elseif game_state=="highscores" then
        update_high_scores()
        update_snow()
    end
end

function draw_game()
    cls()
    draw_snow()
    
    -- draw regular enemies and steeples (except the one being replaced by cross)
    for e in all(enemies) do
        if e.sprite == 2 then
            spr(2, e.x, e.y)
        elseif e.sprite == 5 and not red_cross then
spr(5, e.x, e.y, 2, 1)
spr(21, e.x, e.y+8, 2, 1)
spr(37, e.x, e.y+16, 2, 1)
        end
    end
    
    -- draw red cross if it exists
    if red_cross then
        spr(11, red_cross.x, red_cross.y, 4, 1)     -- top row
        spr(27, red_cross.x, red_cross.y+8, 4, 1)   -- second row
        spr(43, red_cross.x, red_cross.y+16, 4, 1)  -- third row
        spr(59, red_cross.x, red_cross.y+24, 4, 1)  -- bottom row
    end
    
    draw_bullets()
    draw_particles()
    draw_powerups()
    
    -- draw canoe with blinking when invincible
    if not canoe_invincible or time()%2<1 then
        spr(canoe.sprite, canoe.x, canoe.y)
    end
    
    -- draw hud
    print("score:"..score, 4, 2, 7)
    local minutes = flr(total_elapsed_time/60)
    local seconds = flr(total_elapsed_time%60)
    print("temps:"..minutes..":"..tostr(seconds), 4, 14, 7)
    print("maudit:"..flr(devil_meter), 4, 20, 8)
    rectfill(4, 26, 4+devil_meter, 30, 8)
    rect(4, 26, 4+max_devil_meter, 30, 7)
end
function draw_powerups()
 for p in all(powerups) do
  spr(p.sprite,p.x,p.y)
 end
end

function draw_snow()
 for s in all(snow_particles) do
  pset(s.x,s.y,7)
 end
end

function draw_bullets()
 for b in all(bullets) do
  spr(b.sprite,b.x,b.y)
 end
end

function draw_particles()
    for p in all(particles) do
        if p.score then
            -- score particles show text
            print(p.text,p.x,p.y,7)
        else
            -- regular explosion particles
            pset(p.x,p.y,8+p.life%3)
        end
    end
end

function update_title()
    if btnp(🅾️) then
        if not showed_high_scores then
            -- first show high scores
            game_state = "highscores"
            showed_high_scores = true
        else
            -- then go to narrative
            narrative_state = "start"
            game_state = "narrative"
            showed_high_scores = false  -- reset here
            init_game()
        end
    end
end

function draw_title()
    cls()
    draw_snow()
      print("la chasse-galerie", 25, 20, 8)  -- changed to red (color 8)
    print("le jeu pico-8", 32, 30, 7)    -- added subtitle
    print("v2.0", 105, 122, 7)   -- version number
    -- game elements explanation with sprites, moved left
    spr(1, 8, 50)
    print("le canot maudit", 22, 52, 7)
    
    spr(2, 8, 60)
    print("chasse les demons du yable", 22, 62, 7)
    
    -- draw steeple (2 tiles wide, 3 tiles high)
    spr(5, 8, 70, 2, 1)
    spr(21, 8, 78, 2, 1)
    spr(37, 8, 86, 2, 1)
    print("touche pas aux eglises!", 22, 78, 12)
    
    spr(25, 8, 95)
    print("sirop = reduit le maudit", 22, 97, 7)
    
    spr(10, 8, 105)
    print("boit pas au volant", 22, 107, 7)
    
    print("score: "..high_score, 22, 115, 7)
    print("🅾️ pour jouer", 30, 122, blink())
end

function game_over(line1, line2, line3)
    -- set game over state and reason first
    game_state = "gameover"
    game_over_reason = {
        line1 or "",
        line2 or "",
        line3 or ""
    }
    
    -- check and store if it's a high score, but don't enter input state yet
    if score > 0 and add_high_score(score) then
        input_state = "pending"  -- new state to indicate we'll need input later
    else
        input_state = "none"
    end
    
    -- update all-time high score if needed
    if score > high_score then
        high_score = score
    end
end

function update_gameover()
    if input_state == "highscore" then
        -- handle letter scrolling
        letter_select_timer += 1
        if letter_select_timer >= letter_scroll_delay then
            if btn(2) then  -- up
                current_letter -= 1
                if current_letter < 1 then current_letter = #alphabet end
                letter_select_timer = 0
                sfx(0)  -- optional: add scroll sound
            elseif btn(3) then  -- down
                current_letter += 1
                if current_letter > #alphabet then current_letter = 1 end
                letter_select_timer = 0
                sfx(0)  -- optional: add scroll sound
            end
        end
        
        -- add current letter (➡️ button)
        if btnp(1) and #input_name < max_name_length then
            input_name = input_name..sub(alphabet,current_letter,current_letter)
            sfx(1)  -- optional: add confirmation sound
        end
        
        -- delete letter (⬅️ button)
        if btnp(0) and #input_name > 0 then
            input_name = sub(input_name,1,#input_name-1)
            sfx(2)  -- optional: add delete sound
        end
        
        -- confirm entire name (🅾️ button)
        if btnp(4) and #input_name > 0 then
            insert_high_score(input_name, score)
            input_state = "none"
            game_state = "title"
            init_game()
        end

        cursor_blink = (cursor_blink + 1) % 30
    else
        if btnp(4) then  -- 🅾️ button
            if input_state == "pending" then
                input_state = "highscore"
                input_name = ""
                current_letter = 1
                cursor_blink = 0
            else
                game_state = "title"
                init_game()
            end
        end
    end
end

function _draw()
    if game_state=="game" then
        draw_game()
    elseif game_state=="title" then
        draw_title()
    elseif game_state=="narrative" then
        draw_narrative()
    elseif game_state=="gameover" then
        draw_gameover()
    elseif game_state=="highscores" then
        draw_high_scores()
    end
end


function draw_gameover()
    cls()
    draw_snow()
    
    if input_state == "highscore" then
        -- draw high score input screen
        print("nouveau record!", 35, 30, 8)
        print("score: "..score, 35, 40, 7)
        print("entre ton nom:", 30, 50, 7)
        
        -- draw current name with cursor
        local display_name = input_name
        if cursor_blink < 15 then
            display_name = display_name.."_"
        end
        print(display_name, 45, 60, 11)
        print("("..#input_name.."/"..max_name_length..")", 85, 60, 5)  -- show name length
        
        -- draw letter selection
        local letter_y = 75
        -- draw previous letters (if they exist)
        if current_letter > 1 then
            print(sub(alphabet,current_letter-1,current_letter-1), 62, letter_y-8, 5)
        end
        -- draw current letter (larger/highlighted)
        print(sub(alphabet,current_letter,current_letter), 62, letter_y, 7)
        -- draw next letter (if it exists)
        if current_letter < #alphabet then
            print(sub(alphabet,current_letter+1,current_letter+1), 62, letter_y+8, 5)
        end
        
        -- draw controls with new layout
        print("⬆️⬇️ choisir lettre", 20, 95, 6)
        print("➡️ ajouter", 20, 103, 6)
        print("⬅️ effacer", 20, 111, 6)
        
        -- change confirm text color based on whether name is entered
        local confirm_color = (#input_name > 0) and blink() or 5
        print("🅾️ confirmer", 20, 119, confirm_color)
    else
        -- regular game over screen
        local y = 40
        for i, line in ipairs(game_over_reason) do
            if line and line != "" then
                local x = 64 - flr(#line * 2.5)
                x = max(8, x)
                print(line, x, y + i*9, 7)
            end
        end
        
        print("score: "..score, 40, y + 5*9, 7)
        print("🅾️ "..(input_state == "pending" and "entrer score" or "menu"), 
              45, y + 7*9, blink())
    end
end

function draw_high_scores()
    cls()
    draw_snow()
    print("meilleurs scores", 30, 20, 8)  -- use red color (8) for title
    
    if #high_scores > 0 then
        for i=1,#high_scores do
            local y = 35 + i*10
            local score = high_scores[i]
            -- add leading zeros to rank for alignment
            local rank = tostr(i)
            if i < 10 then rank = " "..rank end
            
            print(rank..". "..score.name, 20, y, 7)
            -- right-align scores
            local score_x = 90 - #tostr(score.score)*4
            print(score.score, score_x, y, 7)
        end
    else
        print("pas de scores", 35, 50, 7)
    end
    
    print("🅾️ continuer", 40, 110, blink())
end

function update_high_scores()
    if btnp(🅾️) then
        narrative_state = "start"
        game_state = "narrative"
        showed_high_scores = false
        init_game()
    end
end

__gfx__
00000000000440000080080000a77a00000000000000006666000000000000000000200000044000000110000000000000000888888000000000000000000000
000000000042240008888880aaa77aaa000000000000006776000000000000000002420000400400000440000000000000000888888000000000000000000000
00700700444134440808808077777777000000006666667777666666000000000024420004444440004444000000000000000888888000000000000000000000
00077000004224008888888877777777000000006666667777666666000000000244720040000004004aa4000000000000000888888000000000000000000000
000770004443144400800800aaa77aaa000000000000006666000000000000000244720044444444004aa4000000000000000888888000000000000000000000
00700700004224000088888800a77a00000000000000006666000000000000000024420004044040004aa4000000000000000888888000000000000000000000
00000000444134440088880800a77a00000000000000006666000000000000000002420000400400004aa4000000000000000888888000000000000000000000
00000000000440000080080000a77a00000000000000006666000000000000000000200000044000004444000000000000000888888000000000000000000000
00000000000000000000000000000000000000000000000660000000000000000000000000055000000000008888888888888888888888888888888800000000
00000000000000000000000000000000000000000000006666000000000000000000000000055000000000008888888888888888888888888888888800000000
00000000000000000000000000000000000000000000066666600000000000000000000000600600000000008888888888888888888888888888888800000000
00000000000000000000000000000000000000000000666666660000000000000000000006888860000000008888888888888888888888888888888800000000
00000000000000000000000000000000000000000006666556666000000000000000000068888886000000008888888888888888888888888888888800000000
00000000000000000000000000000000000000000066665555666600000000000000000068888886000000008888888888888888888888888888888800000000
00000000000000000000000000000000000000000666665555666660000000000000000068888886000000000000000000000888888000000000000000000000
00000000000000000000000000000000000000006666665555666666000000000000000066666666000000000000000000000888888000000000000000000000
00000000000000000000000000000000000000006666665555666666000000000000000000000000000000000000000000000888888000000000000000000000
00000000000000000000000000000000000000006666665555666666000000000000000000000000000000000000000000000888888000000000000000000000
00000000000000000000000000000000000000006666665555666666000000000000000000000000000000000000000000000888888000000000000000000000
00000000000000000000000000000000000000006666665555666666000000000000000000000000000000000000000000000888888000000000000000000000
00000000000000000000000000000000000000006666667777666666000000000000000000000000000000000000000000000888888000000000000000000000
00000000000000000000000000000000000000006666666666666666000000000000000000000000000000000000000000000888888000000000000000000000
00000000000000000000000000000000000000006666666666666666000000000000000000000000000000000000000000000888888000000000000000000000
00000000000000000000000000000000000000006666666666666666000000000000000000000000000000000000000000000888888000000000000000000000
00000000000000000000000000000000000000006666666666666666000000000000000000000000000000000000000000000888888000000000000000000000
00000000000000000000000000000000000000006666666666666666000000000000000000000000000000000000000000000888888000000000000000000000
00000000000000000000000000000000000000006666666666666666000000000000000000000000000000000000000000000888888000000000000000000000
00000000000000000000000000000000000000006666666666666666000000000000000000000000000000000000000000000888888000000000000000000000
00000000000000000000000000000000000000006666666666666666000000000000000000000000000000000000000000000888888000000000000000000000
00000000000000000000000000000000000000006666666666666666000000000000000000000000000000000000000000000888888000000000000000000000
00000000000000000000000000000000000000006666666666666666000000000000000000000000000000000000000000000888888000000000000000000000
00000000000000000000000000000000000000006666666666666666000000000000000000000000000000000000000000000888888000000000000000000000
00000000000000000000000000000000888888888888888888888888888888880000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000888888888888888888888888888888880000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000888888888888888888888888888888880000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000888888888888888888888888888888880000000000000000000000eee000000000888888888880000000000000000000
00000000000000000000000000000000888888888888888888888888888888880000000000000000000000eee000000000888888888880000000000000000000
00000000000000000000000000000000888888888888888888888888888888880000000000000000000000eee000000000888888888880000000000000000000
0000000000000000000000000000000088888888888888888888888888888888000000000000000000ee000e00ee000000888000008880000000000000000000
00000000000000000000000000000000888888888888888888888888888888880000000000000000000eeeeeeee0000000888000008880000000000000000000
000000000000000000000000000000008888888888888888888888888888888800000000000000000000000ee000000000888000008880000000000000000000
000000000000000000000000000000008888dddddddddddddddddddddddd888800000000000000000000000e0000000000888000008880000000000000000000
000000000000000000000000000000008888dddddddddddddddddddddddd88880000000000000000000000eee000000000888000008880000000000000000000
000000000000000000000000000000008888dddddddddddddddddddddddd8888000000000000000000000eeeeee0000000888000008880000000000000000000
000000000000000000000000000000008888dddddddddddddddddddddddd8888000000000000000000000eeeee00000000888000008880000000000000000000
000000000000000000000000000000008888dddddddddddddddddddddddd88880000000000000000000000e0e000000888888008888880000000000000000000
000000000000000000000000000000008888ffffffffffffffffffffffff88880000000000000000000000000000000888888008888880000000000000000000
000000000000000000000000000000008888ffffffffffffffffffffffff88880000000000000000000777777707777888888008888880000000000000000000
000000000000000000000000000000008888fffff00000ffff00000fffff88880000000000000000000777777777777000000000000000000000000000000000
000000000000000000000000000000008888ffffffffffffffffffffffff88880000000000000000000777777777777000000000000000000000000000000000
000000000000000000000000000000000000ffffffffffffffffffffffff00000000000000000000000666a77777776000000000000000000000000000000000
000000000000000000000000000000000000fffff44444ffff44444fffff00000000000000000000000666aaaaaaa66666666600000000000000000000000000
000000000000000000000000000000000000fffff44444ffff44444fffff00000000000000000000000666aaaaaaa66666666600000000000000000000000000
000000000000000000000000000000000000fffff11111ffff11111fffff00000000000000000000000666aaaaaaa66666666600000000000000000000000000
000000000000000000000000000000000000fffff11111eeee11111fffff00000000000000000000000666aaaaaaa66000066600000000000000000000000000
000000000000000000000000000000000000fffff11111eeee11111fffff00000000000000000000000666aaaaaaa66000066600000000000000000000000000
0000000000000000000000000000000044444444411111eeee111114444444440000000000000000000666aaaaaaa66000066600000000000000000000000000
0000000000000000000000000000000044444444411111eeee111114444444440000000000000000000666aaaaaaa66000066600000000000000000000000000
0000000000000000000000000000000044444444411111eeee111114444444440000000000000000000666aaaaaaa66666666600000000000000000000000000
00000000000000000000000000000000444444444446666666666444444444440000000000000000000666aaaaaaa66666666600000000000000000000000000
00000000000000000000000000000000444444444446666666666444444444440000000000000000000666aaaaaaa66666666600000000000000000000000000
00000000000000000000000000000000004444444446666666666444444444000000000000000000000666666666666000000000000000000000000000000000
00000000000000000000000000000000004444444444444444444444444444000000000000000000000666666666666000000000000000000000000000000000
00000000000000000000000000000000004444444444444444444444444444000000000000000000000666666666666000000000000000000000000000000000
0000000000000000000000000000000000000000900000000a900000000000090000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000009000000000900000000000090000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000009900000000900000000000990000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000009000000009a0000000000990000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000009000000009a0000000000990000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000009000000009a0000000000900000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000009000000009a000000000a900000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000009900000000999000000009900000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000009900000000a9000000009000000000000000000000000000000000044444444000000000000000000000000
0000000000000000000000000000000000000000009900000000900000009a000000000900000000000000000000000044444444000000000000000000000000
0000000000000000000000000000000000000000000900000000900000009000000000a900000000000000000000000006666660000000000000000000000000
000000000000000000000000000000000000000090090000000090000000900000000a9000000000000000000000000066166166000000000000000000000000
00000000000000000000000000000000000000009669666666669000000090000000a99000000000000000000000000006166160000000000000000000000000
00000000000000000000000000000000000000006666666666669a0000009000000a9900000000000000000000000000066ee660000000000000000000000000
0000000000000000000000000000000000000000666666666666699999999a000099900000000000000000000000000044dddd44000000000000000000000000
00000000000000000000000000000000000000006666666666666699999999aa0990000000000000000000000000000044444444000000000000000000000000
00000000000000000000000000000000000000006666666666666699999999999900000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000006666666666699999999999999990000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000006666666669999999999999999999900000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000666699999996669999999999999a990000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000666699999996966699666666666666a000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000006699999999666696666666666666666600000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000009999999666696966666666666666666a00000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000009999999699966666996666666666666600000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000009996666666666966999666666666666600000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000009666666669966669669999996666666600000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000006666666666666696666666666966666600000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000006666666666666666666666666666696600000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000006666666666666666666666666669666600000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000006666666666666666666666666666666600000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000006666669996666666666666666666666600000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000009999999999999999999666666666666600000000000000000000000000000000000000000000000000000000
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000770077007707770777000007770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00007000700070707070700007007070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00007770700070707700770000007070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000070700070707070700007007070000000000000000000000000000000000000000000000000000000000000000000007000000000000000000000000000
00007700077077007070777000007770000000000000000000000000000000000000000000000000000000000000070000000000000000000000000000000000
00000000000088888800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000080880800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000888888880000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000008008000000000000000000000000007000000000000000000007000000000000000000000000000000000000000000000000000000000000000
00000000000008888880000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000008888080000000000000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000008008000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00007700777070707770777070700000770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00007070070070707000707070700700070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
70007070070070707700777070700000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00007070070077707000707070700700070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00007070777007007770707007700000777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00008880888080808800888088800000880088800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00008880808080808080080008000800080000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00008080888080808080080008000000080000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00008080808080808080080008000800080000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00008080808008808880888008000000888000800000070000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007000000000000000000000000000000000
00007777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777700000000000000000000000
00007888888888888888880000000000000000000000000000000000000000000000000000000000000000000000888888000000700000000000000000000000
00007888888888888888880000000070000000000000000000000000000000000000000000000000000000000000808808000000700000000000000000000000
00007888888888888888880000000000000000000000000000000000000000000000000000000000000000000008888888800000700000000000000000000000
00007777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777700000000000000000000000
00000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000088888800000000000000000000000000000
00000000000000000000000000007000000000000000000000000000000000000000000000000000000000000000088880800000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080080000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000070000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007000000000000000000
00000000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000006666000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000006776000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000006666667777666666000000000000000000000000000000000000000000007000000000000000000000000000000000000000000000000000000
00000000000006666667777666666000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000006666000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000006666000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000006666000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000006666000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000660000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000006666000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000066666600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000666666660000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000006666556666000000000000000000000000000000000000070000000000000000000000000000000000000000000000000000000000000000
00000000000000066665555666600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000666665555666660000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000006666665555666666000000000000000000000000000000000000000000000000000000000000000000000000000000070000000000000000000
00000000000006666665555666666000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000006666665555666666000000000000000000000000000007000000000000000000000000000000000000000000000000000000000000700000000
00000000000006666665555666666000000000000000000000000000000000000000000000000000000000000000000000000000007000000000000000000000
00000000000006666665555666666000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000006666667777666666000000000000000000000000000000440000000000000000000000000000000000000000000000000000000000000000000
00000000700006666666666666666000000000000000000000000000004224000000000000000000000000700000000000000000000000000000000000000000
00000000000006666666666666666000000080080000000000000000444134440000000000000000000000000000000000000070000000000000000000000000
00000000000006666666666666666000000888888000000000000000004224000000000000000000000000000000000000000000000000000000000000000000
00700000000000000000000000000000000808808000000000000000444314440000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000008888888800000070000000004224000000000000000000000000000000000000000000000000000000000000070000
00000000000000000000000000000000000080080000000000000000444134440000000000000000000000000000000000000000000000000000000000000007
00000000000000000000000000000000000088888800000000000000000440000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000088880800000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000080080000000000000000000000000000000000000008008000000000000000000000000000000000000000000000
00000000000000000000000000000000000000007000000000000000000000000000000000000088888800000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000080880800000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000888888880000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000008008000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000008888880000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000008888080000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000008008000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000700000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000007000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000007000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000700000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000007000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000070000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000070000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
70000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000008008000000000000000000000000000000000000700000000000000070000000000000000000000000000000
00000000000000000000000000000000000000088888800000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000080880800000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000888888880000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000008008000000000000000000000000000000000000000700000000000000000000000000000000000000000000
00000000000000000000000000000000000000008888880000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000008888080000000000000000000000000000000000000000007000000000000000000080080000000000000070
00000000000000000000000000000000000000008008000000000000000000000000000000000000000000000000000000000000000888888000000000000000
00000000000000000000000000000000000000000007000000000000000000000000000000000000000000000000000000000000000808808000000000000000

__sfx__
001000000b2000b200282500c2000c2000d2000d2000d2000e2000e200242000d200282001820018200182000d200162000f200162000f2001c200152001c2001a20016200252003f2001c2001c2001c2001c200
001000000c2501225028250196001a6001a6001b6003460034600316003060022600280001a60019600186001760015600146001360013600186001b6001d6001f6002160026600080001f6001c6001a60017600
001000001730017300173001730017300030501b30024300313003130031300313002b3002c3002c3002c3002d300273001230015300153001530015300153003405015300143001430013300123001230012300
0010000012250242503a3003a3003a3003a3003a30039300373003730035300040003330033300323002f30029300133002700012300113001030010300123001330013300133001330011300133001330013300
0010000018250172500b3000b3000b300370000b3000b3000b3000a30009300083003430035300353002f3002f30030300313002f3002f3002e3002d3002c300090002d3002d3002c3002c3002b300283002a300
000e00000f270162701427012270162701627017070162701427014270122700f2701227016270142701227000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
03 05050505
00 41424344
00 41424344
00 41424344
00 41424344
00 45424344

