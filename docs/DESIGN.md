# Par & Parcel: design

A course-builder golf tycoon. Three pillars: **build the course, run the
club, play the round.** The name is the game: par on the course, parcels
of land to buy round it. It was chosen to be original; the game owes its
shape to the course-builder classics of the early 2000s and shares no name
or art with them.

Engine: Godot 4.7, typed GDScript, Forward+ renderer. The graphics backend
is pinned in `project.godot`: Metal on macOS, Vulkan on Windows and Linux.

## Feature list and status

Status key: **Built** works end to end and is covered by a test or a scripted
check. **Basic** works but is thin. **Not yet** is planned.

### Build the course

| Feature | Status | Notes |
| --- | --- | --- |
| Paint terrain | Built | Fairway, green, tee, bunker, water, rough, deep rough, cart path. Four brush sizes. Priced per tile. |
| Shape the land | Built | Raise, lower, smooth, level. Slopes change every bounce and roll. Hollows hold rainwater. |
| Green elevation | Built | Putts break with the slope. Contour lines every 25 cm. |
| Biomes | Built | Lush parkland, highlands, desert and volcanic. Each has its own land, climate, turf behaviour, plants, colours and landmark. |
| Volcano | Built | Volcanic courses have a live volcano. Hazards are lava. Eruptions throw lava bombs that crater the ground, burn trees, lay ash and send lava flows downhill, which cool to rock. The map is changed for good. |
| Scenery | Built | Two trees, a shrub and a boulder per biome, flower beds, fountain, benches, a landmark. Trees block low shots. |
| Facilities | Built | Clubhouse (upgradable), restroom, snack bar, drink stand, vending machine, bar, bench, ball washer, cart barn, putting green, driving range, bridge. Golfers have hunger, thirst, bladder and tiredness; a need met on the course lifts their mood and earns concession money, a need unmet sours it, and golfers who warm up on the practice green or range arrive happier and play a little better. Eating gets a burp, a restroom a flush, a drink a slurp, a bottle at the bar a pop. The vending machine is the cheap answer to thirst and hunger both ($4 and $7, lit at night, used when no stand is near). The bar is the owner's gamble: a round of drinks is $14 a head and makes a golfer much happier and forgiving of small things, but a drinker takes longer over every shot, walks slower, sprays the ball, is hit harder by anything that really goes wrong and snaps sooner. It wears off over about two holes. Socialites, high rollers and thrill seekers drink readily; purists and golfers in a hurry hardly ever; tournament pros never mid-round. |
| Cart paths | Built | Golfers and carts route along paths and move faster on them. |
| Lay out holes | Built | Click a tee, click a green. While the pin is being placed the tool draws the line of play and shows the par and the yardage, and every build tool says 1 tile ≈ 5.5 yd. Par comes from the length of that line (the cheapest route along the fairway, smoothed), with the same 225 m and 430 m thresholds, and it is remeasured when the ground under the hole changes. A hole that has already been played keeps its scorecard honest: old scores are shifted onto the new par. Saves store the par they were scored against. Older saves did not, so loading one assumes the old straight-line par and shifts the scorecard onto the route. Best, aces and medals already given stay as they are. Move, rename, reorder or close a hole at any time. The Holes panel carries a scorecard: every hole's par, yards, average score, share of birdies and bogeys, how much fun golfers find it and what it pays, with the hardest, easiest, favourite and least liked holes named and the complaint behind the least liked. |
| Hole ratings | Built | Every hole is test-played by simulated golfers of six kinds. It gets a type (Breather, Freeway, Precise, Creative, Challenge, Heroic, Strategic, Classic), expected scores and comments. |
| Buying land | Built | The property is sold in parcels. Scenarios can start you on a corner of the map. |
| Home sites and resort | Built | Sell home sites to members, then tennis courts, a hotel, a marina and an airstrip as the club grows. |
| Camera | Built | Move, zoom, turn and tilt, from the whole property down to standing beside a golfer. Works with a one-button mouse, a trackpad, a wheel mouse, the keyboard, or the Camera bar on screen. Click a golfer and follow them. |
| Map overlays | Built | Moisture, turf health, height, mood, contours, build grid. The mood map is where golfers have lately been pleased or annoyed, and it fades over a couple of days. A thought in the golfer card remembers the spot and jumps the camera there. |
| Draft holes | Built | A hole laid out by hand starts closed. Test plays it with the lab golfers and marks where their tee shots stopped. Open lets the public on. Generated holes, and saves that never stored the flag, stay open. |
| Undo | Not yet | Bulldoze and repaint instead. No refunds. |
| Streams, pot bunkers, waste areas | Not yet | |

### Run the club

| Feature | Status | Notes |
| --- | --- | --- |
| Green fees hole by hole | Built | Nobody sets a price. Each golfer pays as they leave each green, by how much they enjoyed that hole: nothing for one they hated, a tip on top for one they loved. Wealth, personality, the course's rating and membership discounts scale it. |
| Golfer satisfaction | Built | Every golfer has a mood and a list of thoughts you can read. The course average drives the rating. |
| Pace of play | Built | Each party is timed from when it heads for a hole until it walks off, waiting included. The scorecard shows the recent average per hole on the course clock, what those averages add up to for a round, and which hole is the bottleneck. A round over five hours is named as such. |
| Tee times and slow play | Built | One party on a tee at a time. The golfer hitting stands on the box, their partners in an arc behind the marker, and every other party waits in a line down the hole's own axis, eight metres back and six between parties, in order of arrival, shuffling forward as the party ahead tees off. Golfers stepping up to a spot step round anyone already standing there. Nobody hits into people: a golfer whose landing area has anyone in it holds the shot until it clears, and only gives up after two and a half minutes of nothing changing (forty-five seconds when the only one in the way is the owner, stood still), which the feed reports. A drunk golfer skips the look with probability equal to how drunk they are. Waiting hurts as it happens: the first twelve seconds are free, then a little satisfaction a second, less for the patient, half as much on a bench; at half a minute they grumble about it, and a hole that was mostly waiting leaves a sour note at the end. |
| Personalities | Built | Twelve kinds of customer. Some are easy to please, some never are. Each cares about different things and pays differently. |
| Needs | Built | Thirst, hunger, restroom and tiredness. Golfers detour to the right facility if there is one. |
| Membership | Built | Golfers who loved their round join. Six tiers: Basic, Advanced, Bronze, Silver, Gold, Platinum. Each member has hidden wishes that must be met to move up; hints surface after misses. Dues, a discount on what they pay per hole, resignations. |
| Golfers hit by balls | Built | Victims fall over, lose their temper, post about it, and sometimes sue. Broken windows too. |
| Tantrums | Built | A golfer whose mood hits bottom has a fit on the spot: a few seconds of stamping and shouting, then a punch for a partner or a club thrown so you see it fly and lie where it lands (or splash). A marshal nearby walks them off first. Most of them then storm off the course at a march, without a club, and say so on the feed. `--ragetest[=toss]` shows one. |
| Weeds and pests | Built | Both spread tile to tile. Weeds grab the ball. Mounds knock putts off line. Weeds look like weeds: ragged patches of coarse, darker broadleaf growth that yellow as they thicken, with standing dandelions and plantain spikes growing out of the patches close up, on fairway, green and rough alike. `--weeds=all` shows every level. |
| Weeds follow the mood | Built | Below 60% golfer satisfaction weeds come up faster, three times as fast at 30%; above 60% a little slower. Weeds then grab balls and sour moods, so a neglected club spirals until greenkeepers, facilities or better holes break the loop. The owner is told the first time it bites. |
| Staff | Built | Greenkeepers, exterminators, marshals, a drinks cart and a club pro, hired and promoted from the Staff panel. Wages, promotion. |
| Weather and wind | Built | Clear, cloudy, drizzle, rain, thunderstorm, by season and biome. The wind shifts, and every so often a gust blows half as hard again for a few seconds and swings it round. The top bar says when it is gusting, you can hear a gust arrive, and on a dry day faint streaks drift with the wind so you can see which way it blows and how hard. |
| Free play starts empty | Built | Free Play is a bare property with a clubhouse and $30,000: you lay out every hole. The land round you is for sale in parcels from the Build panel, each dearer than the last. (The old three-hole free play lives on as a hidden scenario for the tests and measuring scripts.) |
| Clubhouse ladder | Built | A starter clubhouse allows three holes. Each of five upgrades allows more (6, 9, 12, 15, 18) and costs more, and each asks for a membership first: more members, members in higher tiers (Advanced, Bronze, Silver, Gold) and a course rating. The Build panel shows the checklist with what the club has now. Scenarios that start with more holes start with the clubhouse to match; the sandbox is not gated. Data in `data/clubhouse.json`. The two top rungs have not been reached in play yet. |
| Difficulty slider | Built | Relaxed, Easy, Normal, Hard, Brutal (`data/difficulty.json`), chosen on the start screen and changeable from the Menu mid-game. Harder levels cut what golfers pay for a hole, make bad moments hit their mood harder and good ones lift it less, speed up weeds, pests and turf wear, and raise wages. The level is saved with the game. |
| Day and night | Built | A clock in the top bar. The sun crosses the sky, dusk and dawn colour it, stars come out. A full day and night takes five minutes at normal speed and runs apart from the calendar, as in most park and city builders. |
| Lighting and night golf | Built | Floodlights and lamp posts (Build, Lighting), and buildings light their surroundings. Golfers play on after dark, but on an unlit hole they see poorly, enjoy it less and pay less, and few new golfers arrive (about a fifth of the daytime rate; the arrival clock runs at the rate of the moment, so dusk slows it rather than letting an afternoon's queue arrive at midnight). A hole lit along its line of play, tee to green, plays as by day. Holes shows how much of each is lit. |
| Wet ground changes ball physics | Built | Less bounce, less roll, plugged balls when soaked. Firm and fast when dry. |
| Tournaments | Built | Five tiers. You pay the purse; sponsors and the gate pay you back. Leaderboard. You can enter your own. |
| Scenarios and free play | Built | Seven challenges with goals and deadlines, free play, and a sandbox with a choice of biome. |
| Random events | Built | Celebrity visits, heat waves, pest outbreaks, weed blooms, outings, storm fronts, magazine reviews, viral clips, sponsors, eruptions, visiting dignitaries who bring land, landmarks or cash. |
| Social feed ("Birdie") | Built | Scrolling ticker and a full feed. Golfers post about what happens to them. |
| Manager skill tree | Built | |
| Rankings and awards | Built | Year-end world ranking, hole awards, thirty accomplishments. |
| Finances | Built | Monthly books by category, history, debt interest, warnings from the board. |
| Wildlife | Built | Animals wander the course and bolt from flying balls. |
| Stories | Built | Eight scripted stories (`data/stories.json`) with named characters who come back round after round: a romance that needs a bench by the water, a grudge that ends in a match the owner can join, a tour pro's comeback, an heiress shopping for a view, a prodigy who wants a tournament to enter, a critic, an influencer and a couple who want one quiet hole. Each has chapters, requests of the owner with deadlines, and two endings. Besides those, every group arrives with a one-line story for the round. |
| Save and load | Basic | Course, money, staff, skills, members, stories, records, and the dice, so a loaded game continues the same sequence instead of drawing from the clock. Golfers mid-round are not saved. Autosaves monthly. A loading screen covers a new game or a load: the fairway backdrop, what is happening, a bar, one tip (`data/tips.json`). Saves live in the game's own folder under Application Support; saves left under the earlier folder names are brought across at startup. Test runs use a separate slot and never touch the real save. |
| Sprinklers and irrigation | Not yet | Turf only scorches in heat waves for now. |
| Spectators at tournaments | Built | A gallery of up to four hundred and eighty follows the leaders, or the owner when the owner is playing, with knots of them along the other holes in play. They turn to watch the ball and raise their arms when the crowd cheers. One instanced crowd, eight draw calls, no per-frame script work (`crowd_view.gd`). |
| Ball effects | Built | Sand off a bunker shot, a divot and grass from an iron, a ring and droplets from water, embers from lava, dust off a path, wherever the ball lands (`fx_view.gd`, from the sounds the simulation announces). |
| Scorecard and designer tips | Built | The Holes panel carries a scorecard: every hole's par, yardage, average score and how the scores fell, with the hardest, easiest and favourite called out. Under a hole that has been played a few times, a designer's tip says what would make it better, from what the test golfers found and what the paying ones say. |

### Play the round

| Feature | Status | Notes |
| --- | --- | --- |
| Play your own course | Built | Any hole, or all of them. A three-click swing in the Everybody's Golf manner: one press starts the marker up the bar, the second sets the power where you stop it (past the 100 mark is an overswing: more distance, less margin), and it comes straight back for the third press on the line. A wide green band flies straight; the thin bright line in its middle is a flush strike, which adds a little distance and spin. Miss the band and the ball curves, early hooks and late slices, the further out the worse; miss by a lot and the strike is poor. Let it run past the line and the swing goes anyway. No second goes. A long club or a bad lie shrinks the band, difficulty scales it, Ball Striking widens the flush line and Tempo slows the marker. Same physics as the computer golfers. |
| Stick swing | Built | With a controller the right stick swings instead: pull it back and the backswing grows for as long as you hold it, push it forward to hit. A push straight ahead is flush; off to one side bends the shot; dawdling between back and forward loses power. Letting the stick settle without pushing calls the swing off. |
| Broadcast camera | Built | Your long shots are shown the way television shows them: the camera flies along behind the ball, drawing in as it climbs and keeping a high ball in frame, and once the ball is down near the green it cuts to the reverse angle, from the ball toward the flag. Putts keep the putting view. |
| Shot shapes | Built | Draw, fade, high backspin, low punch and flop, unlocked through your golfer's attributes. |
| Lies | Built | Where the ball sits decides the next shot (`data/lies.json`). Rough takes spin off; a ball there can sit up (a flyer: hot, little spin) or sit down (short and wild). Deep rough can bury it or perch it. Sand makes a clean strike harder, and a ball that drops steeply into a bunker can plug. Wet grass takes spin off. A slope under the ball changes the launch: uphill flies higher, downhill lower, ball above your feet draws, below fades. The play panel names the lie and says what to expect. Computer golfers read the same lie, the better ones allowing for more of it. |
| Computer golfers manage the course | Built | A golfer picks a landing spot, not a direction: thirteen lines either side of the flag, each weighed by how much trouble it lands in. Rough, deep rough, sand, trees, water and out of bounds cost fractions of a stroke, water and out of bounds most of one, so a dogleg is played round its corner and a fairway is preferred to a shorter line through the trees. Trees in the way count for the whole flight, and a ball still under the canopy counts for much more than one flying over them. How much the trouble weighs depends on the golfer's imagination: duffers aim at the flag and hope, thoughtful players lay back. |
| Spin | Built | Backspin is carried on the ball and bites when it lands: a normal wedge hops and runs out a few yards, the high backspin shot checks and can pull back a yard or two on a green or fairway, never out of rough. Sidespin kicks the ball the way it was curving. Spin is lost to rough, sand, wet grass and anything the ball hits. The ball is drawn with a painted line so you can see it turning. |
| Wind in flight | Built | The wind is stronger aloft than near the ground, so a punch is blown about far less than a high shot. It is slack among trees, lifts the ball where it blows up a slope and presses on it down the far side, and every real shot meets its own eddies. Over lava the rising heat holds the ball up. The play panel gives the wind as it bears on the shot you are aiming, and after the shot says how far the wind moved it. |
| Out of bounds | Built | White stakes mark the edge of the club's land. A ball is out only if it comes to rest beyond them (it may bounce or roll back in), or leaves the map. The penalty is stroke and distance: one stroke, and the shot is played again from the same spot. The aiming ring turns red when the shot as aimed would finish out. A ball lost in water is never dropped on land that is not the club's. |
| Collisions and ricochets | Built | The ball bounces off tree trunks, walls, roofs, boulders, posts, benches and landmarks, each with its own bounce. Leaves slow it and branches can stop it. Rolling balls bounce off things and bog down in bushes. Computer golfers plan with the same physics. |
| Branded clubs | Built | Seven fictional brands across woods, irons, wedges and putter. Power versus accuracy versus forgiveness. |
| Golf balls with power-ups | Built | Nine balls: distance, spin, water-skipping, mud-proof, wind-cutting, straight-flying, sand, cup magnet. |
| Your golfer | Built | Eight attributes, ten levels each: Power, Accuracy, Ball Striking, Approach, Putting, Recovery, Spin, Luck. Perks unlock along the way (shot shaping, the flop, reading greens and wind). Bought with skill points. |
| Earning skill points | Built | Medals for your best score on each hole (bronze for par, silver for birdie, gold for eagle), 42 one-time challenges across driving, approach, putting, recovery, scoring and career, a point for every full round at par or better, and golfer levels. |
| Money matches | Built | Visiting pros challenge you for a stake. |
| Enter your own tournaments | Built | |
| Golfer editor, taking your pro to other courses | Not yet | |
| Multiplayer | Not yet | |

### Presentation

| Feature | Status | Notes |
| --- | --- | --- |
| Terrain | Built | Rounded, organic outlines rather than tiles. Photographic ground, mowing stripes, bunker lips, shore foam, puddles in hollows, cloud shadows. |
| Standing grass | Built | The rough is real blades near the camera, tall in deep rough. It follows painting and sculpting instantly. The same layer stands the weeds up, in every biome, so a tuft on a weed patch is a dandelion or a plantain in its own colours. |
| Trees and plants | Built | Leaf, needle and frond canopies that sway in the wind, with a lighter version in the distance. |
| Seasons | Built | The year runs March to October and the course shows it: fresh pale leaves and lush grass in spring, deep summer green, then from September the broad-leaved trees turn, each at its own moment, most to gold and some to red, while conifers and palms stay green and the grass goes a little tired and golden. Weaker in the desert, where little turns. `--day=200` shows mid-October. |
| Buildings and props | Basic | Modelled in code with real plaster, brick, tile, slate, timber and stone. Recognisable, not ornate. |
| People | Basic | Jointed figures with faces, hair and hat variety, animated in code: walking, address, swing, putt, cheer, falling over, a tantrum, a storming-off march. They move at the simulation's pace, so they stand still when the game is paused. Not motion-captured characters. |
| Lighting | Built | Soft sun shadows, ambient occlusion, bounce light, bloom, haze, depth of field, weather-driven sky. |
| Graphics presets | Built | Low, Medium, High, Ultra in the Menu. An optional governor dials effects back when the frame rate cannot be held and restores them when it can. |
| Display settings | Built | A Display and graphics card in the Menu: full screen or window (F11 or Control-Command-F switch too), window size from a list that fits the display, the 3D picture's resolution (preset default, 720 to 2160 lines, or native) separate from the graphics preset, the preset itself, the frame-rate governor, and the interface size from 80% to 110%. All remembered. Full screen owns the display so frames go straight to it instead of through the desktop compositor. The switch waits until the game is the front app, because macOS ignores it otherwise. Confirmed on the owner's screen. Apple's overlay reports Direct rather than Composited only when the display runs at its default scaling (a scaled resolution forces macOS to resample every frame) and, on a notched Mac, when the app may cover the camera housing, which the released build declares in its Info.plist. |
| Controller | Built | Any pad Godot recognises works (Xbox, PlayStation, Switch); buttons are read by position and named after the pad plugged in. The left stick moves a pointer that sends the same events as a mouse, so every panel, menu and build tool works unchanged: A clicks and holds to paint, B goes back, the bumpers step through the panels, the right stick turns and tilts, the triggers zoom, and pushing the pointer against a screen edge moves the map. The d-pad changes game speed and scrolls lists; in a menu it steps from button to button and moves sliders. Start opens the menu and Select pauses. In a round the stick aims, A swings, the bumpers change club, X changes shot shape, Y changes ball, and B stops the power meter or, pressed twice, leaves the round. The pad buzzes on the strike (can be turned off on the Controls card). Moving the mouse hides the pad's pointer; touching the pad brings it back. `--demo=gamepad` drives all of it with synthetic pad events. Not yet tried on a physical controller. |
| Sound effects | Built | Fifty-one effects, all Ogg Vorbis: four club strikes plus a bunker shot and a grass layer for shots from rough, landings, the ball in the cup, splashes and lava sizzle, a ricochet per material, an out-of-bounds marker, a wind gust, applause, coins, interface sounds, thunder, eruptions. Heard at full strength up close and about 2 dB fainter per doubling of camera distance. Synthesised by `tools/make_sounds.py` and encoded by `oggenc`. Short effects are decoded once at load so playing one costs nothing. |
| Voices | Built | Golfers talk nonsense among themselves while they walk and wait: five synthesised voices, six lines each, one voice per golfer for the day. One speaks, often another answers, and nobody talks over a swing. A chip-in or long putt gets a cheer, an ace an ovation, a missed short putt or a ruined hole a groan, a ball in the water or out of bounds a groan, someone hit by a ball a boo. At most three voices at once. Not yet judged by ear. |
| Ambience | Built | Birdsong by day, crickets at night, wind that follows the weather, rain, a rumble on the volcano, and a mower when a greenkeeper is at work nearby. |
| Music | Built | Seven public-domain pieces by other composers, about 21 minutes, all Ogg Vorbis: piano and guitar by day, quieter piano and ambient after dark, with a pause between tracks. Volume sliders and Next track in the Menu. |
| Tutorial | Built | A coach for the first round, started automatically on a fresh Free Play and any time from Menu, Tutorial. Thirteen steps (`data/tutorial.json`): the land, Build, a tee, a green, a fairway, laying out the hole, watching the first golfer pay, a drink stand, a greenkeeper, buying land, the clubhouse rule, a round of your own, and where to look next. The green step gives the scale as it is: a tile is five metres, about five and a half yards, and two hundred to three hundred yards is thirty-seven to fifty-five tiles. The card says what to do and why, the toolbar button it needs pulses gold, and each step moves on by itself when the game shows it was done. `--demo=tutorial` drives every step. |
| Linux | Built | Runs on the owner's Linux box (Debian 13, Radeon RX 6900 XT): Vulkan Forward+ through Mesa's RADV, the headless suite at 438 checks, and the play, panels, camera and controller demos all pass with the same picture as macOS. `./linux.sh` syncs, tests and screenshots it from the Mac. Windows is still untested. |

## How it is put together

```
scripts/core/    The whole game as plain data and rules. No rendering.
scripts/view/    Draws the simulation and turns input into simulation calls.
scripts/ui/      The interface.
scripts/game.gd  Autoload: data, the running Sim, the game clock, settings.
data/*.json      Clubs, balls, staff, skills, tournaments, scenarios, biomes,
                 personalities, membership, accomplishments, names, feed lines.
shaders/         Terrain, grass, foliage and sky.
assets/textures  Ground, bark, stone and building materials, and the foliage atlas.
tools/           Scripts that fetch or paint the textures.
tests/           Headless tests and the balance ledger.
```

**The simulation never touches the screen.** `Sim` owns a `Course`, the
weather, the grounds, the crew, the visitors and the books. It advances in
fixed steps of 1/60 s. The views read it every frame and interpolate between
steps, so motion is smooth at 120 Hz, or any refresh rate, and at any game
speed. This is also why the tests can run a whole season in seconds.

**The course is a tile grid** (5 m tiles) with a height at every corner.

**One ball model for everyone.** Drag, lift, sidespin, wind, bounce and roll
live in `ball.gd`. Computer golfers, the player, the aiming preview, the hole
ratings and the club distance tables all use it. Backspin is a quantity the
ball carries (the speed of its surface) and spends on each bounce; the air
it flies through is worked out where the ball is (`Ball._air`): the steady
wind scaled by height, shelter, slope, and for a real shot its own eddies.
A golfer planning a shot sees the steady wind only. Gusts and eddies draw
from their own random numbers, so they never disturb the rest of the game.

**The swing is a small state machine** in `play_mode.gd`: AIM, POWER (the
marker climbing), ACCURACY (the marker falling back to the line), SWING,
FLIGHT, PAUSE. Three presses or a stick gesture drive it; the result of the
third press is one number, the timing, which `_strike` turns into a starting
line and a curve exactly as a computer golfer's spread does. The meter
widget only draws what the state machine says.

**The lie is read, not assumed.** `lie.gd` turns the ground under the ball,
how it is sitting, the wet and the slope into one set of numbers for the
next shot, from `data/lies.json`. The same reading drives the computer
golfers' swing, the player's swing, the aiming preview and the words in the
play panel.

**Collisions are the game's own, not an engine's.** `solids.gd` keeps every
solid thing as a simple shape (upright cylinder, ball, block, gabled roof,
or a volume of leaves) in a grid of buckets, and the ball sweeps its path
against the few shapes near it each step. The shapes are data
(`data/solids.json`), listed per kind of model, and plants use the same
nudge, size and turn as their models, so what you see is what you hit. It
is deterministic on purpose: golfers play each shot forward in their heads
with this code before they swing, thousands of steps a second, which a
general rigid-body engine could not do. (PhysX is NVIDIA's engine and is not
available in Godot; Godot's own rigid bodies are not used for the ball.)

**Golfer AI** scores candidate landing spots using a per-hole routing field,
penalties for hazards, and the golfer's own spread. Better golfers allow for
wind and slope. Errors and mishits come from ability, clubs and lie.

**Content is data.** New club brands, balls, skills, scenarios, tournaments,
biomes, personalities, membership rules and feed lines are JSON edits.

## How it is drawn

Nothing on screen is an imported 3D model. Everything is generated, so the
look can be changed in one place and a new biome is a data edit.

- **Terrain** (`shaders/terrain.gdshader`). Tile type, wetness, turf health
  and weeds arrive in a small data texture, so painting or rain never
  rebuilds geometry. For every pixel the shader measures how much of each
  surface lies nearby, which turns the tile grid into rounded outlines, then
  lays a photograph of that surface over the biome's colour.
- **Grass** (`grass_view.gd`, `shaders/grass.gdshader`). One patch of tufts is
  drawn many times around the camera. Each tuft reads the same data texture
  and a height texture in the shader, so it stands on the land, grows only
  on rough, and takes the ground's colour. Nothing is rebuilt on an edit.
- **Plants** (`flora.gd`, `shaders/foliage.gdshader`). A canopy is a dark core
  wrapped in small cards painted with leaves, needles or fronds from an
  atlas that `tools/make_foliage.py` paints. Lighting follows the whole
  crown. Each kind has a detailed and a light mesh; the light one also casts
  the shadows.
- **Buildings and props** (`world_view.gd`). Lists of simple parts with
  position-mapped materials, merged into one surface per material.
- **People** (`person_fig.gd`). Limbs and torsos turned on a lathe, hung on a
  small skeleton, posed in code every frame.
- **Light and atmosphere** (`weather_view.gd`). Sun, sky, ambient occlusion,
  bounce light, bloom, haze and depth of field, all driven by the weather.

- **Sound** (`sound_desk.gd`). The simulation announces what happened and
  where (`Sim.sound`); the desk decides whether the camera can hear it. Three
  mixing buses (Music, Sound, Ambience) with a limiter on the output.
  Effects are Ogg Vorbis files made from the physics of each sound: struck
  things ring at a few frequencies that die away, impacts add a burst of
  noise, wind and rain are filtered noise, voices are a pulse train through
  moving formant filters. Music the composer published as Ogg is used
  untouched; a measured gain per track evens out their loudness.
- **Night** (`weather_view.gd`, `world_view.gd`). One directional light is
  the sun by day and the moon by night. Every floodlight, lamp post and lit
  building is a real light with no shadows; lamp glass and windows glow.

**Presets.** Low, Medium, High and Ultra change anti-aliasing, shadow
quality, ambient effects, grass thickness, how far detailed trees reach, and
how many lines the 3D picture is drawn at before it is scaled to the window
(810, 945, 1080 and 1440). The interface is always drawn at full sharpness.
Bounce light and shadows that soften with distance are Ultra only: each
costs about a millisecond and adds little.

**What made it fast.** Measured with `./perf.sh`: tree shadows are cast by
plain solid stand-ins instead of every leaf card (the single biggest cost);
the terrain, grass and sky read their noise from a small texture instead of
computing it about forty times a pixel; trees switch to a light version
beyond 165 m.

**Frame rate.** The target is 120 Hz. Measured by wall clock on an Apple M5
Max, in the game's normal window (3200 by 1800 pixels), with the camera
sliding, turning and zooming across the course for ten seconds:

| Preset and scene | Average | Late frames |
| --- | --- | --- |
| High, by day | 120 fps | none |
| High, floodlit night | 120 fps | none |
| High, volcanic | 120 fps | none |
| Medium | 120 fps | none |
| Ultra | 115 fps | 2% |

Uncapped, High runs at about 165 to 215 frames a second. When something else
on the machine is using the processor and graphics chip heavily, frames
arrive late whatever the game does; the governor then dials the picture back
a step at a time, and puts it back if that did not help. Nothing slower than
this Mac has been tested.

## Units

Metres and seconds inside. Yards, feet, mph and Fahrenheit on screen. A
calendar day is 15 seconds at normal speed. A year is eight months (March to
October) of 28 days.

## Balance

First-pass numbers. `./balance.sh` prints a two year ledger for several
management styles. On the three-hole starter course, with nobody setting a
price:

- Two greenkeepers, an exterminator and a marshal keep condition near 90%.
  What a golfer pays for a hole climbs from about $18 to $26 and the club
  makes a steady profit.
- One greenkeeper and no exterminator lets the turf slide. Pay per hole
  peaks, then falls back as golfers stop enjoying themselves.
- With no staff a hole ends up earning about $9, and more and more golfers
  walk off greens without paying at all.

Expect the economy, satisfaction, membership and event rates to need tuning
through play.

## Credits

Ground, bark, stone and building textures are from
[Poly Haven](https://polyhaven.com), released under CC0.
`tools/fetch_textures.py` lists every one and downloads them again.

The music is from [OpenGameArt](https://opengameart.org), all CC0:
"Bluebonnet", "Forget Me Not", "Catmint" and "Daisy" by Kistol, "Sunset
Plains" by Yoiyami, "Morning Sky" by Centurion_of_war and "Another August"
by cynicmusic. CC0 asks for no credit; they are credited here because they
earned it. `tools/fetch_music.py` downloads the files and checks them.
"Sunset Plains" (published as WAV) and "Another August" (published only as
a 320 kbps MP3) are encoded to Ogg Vorbis once by `tools/fetch_music.py` at
quality 8; the other five play from their composers' own Ogg files.
"Another August" is therefore a second lossy generation.

## Building, testing and releasing

`.github/workflows/ci.yml` runs on every push and pull request: every data
file parses as JSON, every script parses (`lint.sh`) and every headless test
passes (`check.sh full`), on Ubuntu with the official Godot binary, whose
checksum is verified. `.github/workflows/release.yml` runs on a `v*` tag or
by hand with a version: it stamps the version into the project, exports
Windows and Linux on Ubuntu with Godot's export templates (cached), wraps
Linux as an AppImage with the desktop file, icon and AppStream data from
`packaging/`, and on a macOS runner exports the app, signs it with the
Developer ID certificate, notarizes it with an App Store Connect API key,
staples the ticket, and builds a disk image with the game's own backdrop
and icon (`tools/mac_release.sh`, which also runs on a desk against the
login keychain). Everything lands on a GitHub release. The secrets it needs
are listed at the top of the workflow and carry the same names as the
owner's other project, so they can be copied. No app stores.

`./build.sh` exports locally once Godot's export templates are installed.
`./linux.sh` runs the game on the owner's Linux machine over ssh: it copies
the project across, runs lint and the headless suite with Godot's Linux
binary, drives the demos on a GPU-backed virtual display (TigerVNC's Xvnc,
which Mesa renders with the Radeon), and brings the screenshots back.
`./linux.sh export` fetches Godot's export templates there, exports a Linux
build and runs it once. A virtual display never signals a frame, so runs
there pass `--novsync`; with no sound server the audio falls back to a
dummy driver, which is expected.

`tools/make_art.gd` draws the icon and the disk image backdrop (`icon.png`,
`tools/dmg/`); run it windowed when the look changes.

## Next steps, roughly in order

1. Play it and tune: fees, wages, satisfaction, membership, event frequency.
2. Sound: have the effects and voices listened to and tuned by ear; replace
   the synthesised voices with recorded ones if a CC0 set turns up; more
   music.
3. Art: richer buildings, animated characters with real clothing, water
   reflections.
4. Undo, streams and more bunker types, irrigation.
5. In-game help beyond the first-round coach.
6. Testing the Windows build, and a physical controller, on real hardware.
7. More scripted stories, golfer editor, career mode for your golfer.
