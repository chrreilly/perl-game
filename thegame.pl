#!/usr/bin/perl
use strict;
use warnings;

use SDL;
use SDL::Event;
use SDL::Events;
use SDLx::App;
use SDLx::Rect;
use SDLx::Surface;
use SDLx::Text;

my $app = SDLx::App->new(
	width => 500,
	height => 500,
	title => "TheGame",
	dt => 0.02,
	exit_on_quit => 1,
);

my $background = SDLx::Surface->load('images/background.png');

my @fire = ();
my @enemies = ();
my @items = ();
my @inventory = ();
my $currentEnemy = undef;
my $mapID = 1;
my $toggleInventory = 0;

my @platforms = spawnMap( $mapID );

my $player = spawnPlayer();

my $text = SDLx::Text->new(
	color => [255, 255, 255, 255],
	size => 15,
);

sub keyboard_event {
    my ( $event, $app ) = @_;

    #User presses key
    if ( $event->type == SDL_KEYDOWN && $player->{health} > 0 ) {
	#Right arrow moves forward
	if ( $event->key_sym == SDLK_RIGHT ) {
	    $player->{v_x} = 2;
	    $player->{direction} = 1;
	}
	#Left moves backward
	elsif ( $event->key_sym == SDLK_LEFT ) {
	    $player->{v_x} = -2;
	    $player->{direction} = -1;
	}
	#Up sets up jump command
	elsif ( $event->key_sym == SDLK_UP && $player->{v_y} == 0 ) {
	    $player->{v_y} = -5;
	}
	#a fires
	elsif ( $event->key_sym == SDLK_a && $#fire < 3 ) {
	    my $side = $player->{direction}+1 ? 'right' : 'left';
	    push @fire, {
		arrow => SDLx::Rect->new( $player->{char}->$side, $player->{char}->y+20, 10, 2 ),
		v_x => 5 * $player->{direction},
	    };
	}
	#i opens inventory
	elsif ( $event->key_sym == SDLK_i  ) {
	    if ( $toggleInventory ) {
		$toggleInventory = 0;
	    } else {
		$toggleInventory = 1;
	    }
	}
	#z picks up items
	elsif ( $event->key_sym == SDLK_z ) {
	    foreach ( @items ) {
		if ( checkCollision( $player->{char}, $_->{drop} ) ) {
		    @inventory = addInventory( $_, @inventory );
		    @items = deleteObject( $_, @items );
		}
	    }
	}
		    
    }
    #Stop horizontal movement when key is released
    elsif ( $event->type == SDL_KEYUP ) {
	if ( $event->key_sym == SDLK_RIGHT or $event->key_sym == SDLK_LEFT ) {
	    $player->{v_x} = 0;
	}
    }
}

sub mouse_event {
    my ( $event, $app ) = @_;

    if ( $event->type == SDL_MOUSEBUTTONDOWN ) {
	my $x = $event->button_x;
	my $y = $event->button_y;

	#Respawn player	
	if ( $player->{health} <= 0 ) {
	    if ( $x <= $app->w-150 && $x >= $app->w-350 && $y <= $app->h-250 && $y >= $app->h-350 ) {
		$player = spawnPlayer( $player->{level} );
	    }
	}
	#Allow player to use items when inventory is open
	elsif ( $toggleInventory ) {
	    foreach ( @inventory ) {
		if ( $x >= $_->{drop}->x && $x <= $_->{drop}->x+$_->{drop}->w && $y >= $_->{drop}->y && $y <= $_->{drop}->y+$_->{drop}->h ) {
		    getItemEffect( $_->{name} );
		    $_->{quantity}--;
		    @inventory = deleteObject( $_, @inventory ) if $_->{quantity} == 0;
		    @inventory = updateInventory( @inventory );
		}
	    }
	}
    }
}

#Player movement
$app->add_move_handler( sub {
    my ( $step, $app ) = @_;
    my $char = $player->{char};
    my $v_x = $player->{v_x};
    my $v_y = $player->{v_y};

    $char->x( $char->x + ($v_x * $step) );
	$char->left( 0 ) if $char->left <= 0;
	$char->right( $app->w ) if $char->right >= $app->w;
    $char->y( $char->y + ($v_y * $step) );
});


#Player jump
$app->add_move_handler( sub {
    my ( $step, $app ) = @_;
    my $char = $player->{char};
    my $gravity = 0.22;

    #Get the current platform index
    foreach ( @platforms ) {
	if ( $char->bottom >= $_->top-4 && $char->bottom <= $_->top+4 && $char->right > $_->left && $char->left < $_->right ) {
	    $player->{platformID} = getIndex( $_, @platforms );
	}
    }

    #Jump physics
    if ( $char->bottom < $platforms[$player->{platformID}]->top ) {
	$player->{v_y} += $gravity;
    }
    #Stop jump if player lands on platform
    elsif ( $char->bottom >= $platforms[$player->{platformID}]->top-4 && $char->right > $platforms[$player->{platformID}]->left &&
		$char->left < $platforms[$player->{platformID}]->right && ($char->bottom-$platforms[$player->{platformID}]->top) < 5 ) {
	$char->bottom( $platforms[$player->{platformID}]->top );
	$player->{v_y} = 0;
    }
    elsif ( $char->right < $platforms[$player->{platformID}]->left || $char->left > $platforms[$player->{platformID}]->right ) {
	$player->{v_y} += $gravity;
    }
});

#Player fire
$app->add_move_handler( sub {
    my ( $step, $app, ) = @_;

    foreach ( @fire ) {
	my $arrow = $_->{arrow};
	$arrow->x( $arrow->x + ($_->{v_x} * $step) );
        shift @fire if $arrow->x > $app->w or $arrow->x < 0;
    }
});

#Enemy movement and collision
$app->add_move_handler( sub {
    my ( $step, $app ) = @_;

    if ( $#enemies < 1 ) {
	@enemies = spawnEnemy( @enemies );
    } else {
	#Allow for randomized enemy movement
	foreach my $enemy ( @enemies ) {
	    $enemy->{monster}->x( $enemy->{monster}->x + ($enemy->{v_x} * $step) ); 
	    $enemy->{changeDirection}++;

	    if ( $enemy->{changeDirection} % int(rand(100)+50) == 0 ) {
		$enemy->{v_x} = 1.2 * (rand(2) > 1 ? -1 : 0);
		$enemy->{changeDirection} = 1;
	    }
	    #Keep enemy on current platform
	    elsif ( $enemy->{monster}->right > $platforms[$enemy->{platformID}]->right ) {
		$enemy->{monster}->right( $platforms[$enemy->{platformID}]->right );
		$enemy->{v_x} *= -1;
	    }
	    elsif ( $enemy->{monster}->left < $platforms[$enemy->{platformID}]->left ) {
		$enemy->{monster}->left( $platforms[$enemy->{platformID}]->left );
		$enemy->{v_x} *= -1;
	    }

	    #Enemy damages player if touched
	    if ( !$player->{hitRecovery} && $player->{health} > 0) {
		if ( checkCollision($player->{char}, $enemy->{monster}) ) {
		    $player->{health} -= calcEnemyDamage( $enemy->{monsterID} );
		    $player->{hitRecovery} = 1;
		}
	    }
	    #Hit recovery stops player from being hit continuously
	    elsif ( $player->{hitRecovery} == 150 ) {
		$player->{hitRecovery} = 0;
	    }
	    elsif ( $player->{hitRecovery} ) {
		$player->{hitRecovery} += 1;
	    }
		
	    foreach ( @fire ) {
		#Check each fire to determine if it has hit enemy
		# if it has, damage enemy
		if ( checkCollision($_->{arrow}, $enemy->{monster}) ) {
		    $currentEnemy = getIndex( $enemy, @enemies );
		    @fire = deleteObject( $_, @fire );
		    $enemy->{health} -= calcPlayerDamage( $player->{level} );
		    #If the enemy dies (health <= 0), remove enemy,
		    # calculate drops and award experience
		    if ( $enemy->{health} <= 0 ) {
			@enemies = deleteObject( $enemy, @enemies );
			@items = calcDrops( $enemy, @items );
			$currentEnemy = undef;
			$player->{experience} += $enemy->{experience};
			( $player->{level}, $player->{experience} ) = checkExp($player->{level}, $player->{experience} );
		    }
		}
	    }
	}
    }
});


sub checkCollision {
    #Check to see if a collision has occured
    my ( $a, $b ) = @_;

    return if $a->bottom < $b->top;
    return if $a->top > $b->bottom;
    return if $a->right < $b->left;
    return if $a->left > $b->right;

    #Collision
    return 1;
}

sub getIndex {
    #Get array index of the current element
    my ( $element, @array ) = @_;

    my ( $index ) = grep { $array[$_] eq $element } 0..$#array;
    return $index;
}

sub deleteObject {
    #Remove array element (enemy, fire, etc.)
    my ( $element, @array ) = @_;

    my ( $index ) = getIndex( $element, @array );
    splice @array, $index, 1;
    return @array;
}

sub spawnEnemy {
    #Push new enemy into enemies array
    my @enemyArray = @_;
    my $platformID = int(rand($#platforms)+.5);
	while ( $platforms[$platformID]->right - $platforms[$platformID]->left < 30 ) {
	    $platformID = int(rand($#platforms)+.5);
	}
    my $spawn_y = $platforms[$platformID]->top;
    my $spawn_x = rand($platforms[$platformID]->w+$platforms[$platformID]->left);
	#Make sure enemy doesnt spawn on top of player
	while ( $spawn_x == $player->{char}->x ) {
	    $spawn_x = rand($platforms[$platformID]->w+$platforms[$platformID]->left);
	}
 
    push @enemyArray, enemyTable( $spawn_x, $spawn_y, $mapID, $platformID );
    return @enemyArray;
}

sub spawnPlayer {
    #Spawn player on left of first platform in map
    my $level = shift || 1;

    return {
        char => SDLx::Rect->new( $platforms[0]->left+5, $platforms[0]->top-40, 15, 40 ),
	direction => 1,
	experience => 0,
        health => calcHealth($level),
        hitRecovery => 1,
	level => $level,
	platformID => 0,
        v_x => 0,
        v_y => 0,
    }
}

sub spawnMap {
    #Draw map according to mapID
    my $mapID = shift;
    my @map = ();

    if ( $mapID == 1 ) {
	push @map, SDLx::Rect->new( 0, $app->h-40, $app->w, 40 ),
	    SDLx::Rect->new( 0, $app->h-95, 20, 10 ),
	    SDLx::Rect->new( 50, $app->h-150, $app->w-100, 20);
    }
    return @map;
}
    

sub enemyTable {
    #Table of enemies according to mapID
    my ( $spawn_x, $spawn_y, $mapID, $platformID ) = @_;
    
    if ( $mapID == 1 ) {
	return {
	    changeDirection => 1,
	    experience => 1,
	    health => 10,
	    monster => SDLx::Rect->new( $spawn_x, $spawn_y-50, 20, 50 ),
	    monsterID => 1,
	    platformID => $platformID,
	    v_x => 1.2 * (rand(2) > 1 ? 1 : -1),
	};
    }
}

sub expTable {
    #Required experience to reach level
    my $level = shift;

    return 8 if $level == 1;
    return 24 if $level == 2;
    return 72 if $level == 3;
}

sub itemTable {
    #Table of items and their 'images'
    my ( $item, $enemy ) = @_;
    my $x = $enemy->{monster}->x;
    my $y = $platforms[$enemy->{platformID}]->top;

    return SDLx::Rect->new( $x, $y-10, 10, 10 ), 0xFF0000FF if $item eq 'smHP';
    return SDLx::Rect->new( $x, $y-10, 10, 10 ), 0x0000FFFF if $item eq 'smMP';
    return SDLx::Rect->new( $x, $y-15, 15, 15 ), 0xFF0000FF if $item eq 'mdHP';
    return SDLx::Rect->new( $x, $y-15, 15, 15 ), 0x0000FFFF if $item eq 'mdMP';
}

sub checkExp {
    #Check player exp, increment level if necessary
    my ( $level, $exp ) = @_;

    if ( $exp >= expTable($level) ) {
	$level += 1;
	$exp = 0;
	$player->{health} = calcHealth($level);
    }
    return ( $level, $exp );
}

sub calcHealth {
    my $level = shift;

    return 5*$level+10;
}

sub calcPlayerDamage {
    my $level = shift;

    return int(rand(2))+2 * $level;
}

sub calcEnemyDamage {
    my $monsterID = shift;

    return int(rand(2))+2 * $monsterID;
}

sub calcDrops {
    #Determine what enemy drops, if anything
    my ( $enemy, @drops ) = @_;
    my $monsterID = $enemy->{monsterID};
    my $random = rand(1);
    my $numberItems;

    $numberItems = 0 if $random <= 0.75;
    $numberItems = 1 if $random > 0.75 && $random <= 0.95;
    $numberItems = 2 if $random > 0.95;

    for ( 1..$numberItems ) {
	my $item;
	$random = rand(1);
	if ( $monsterID == 1 ) {
	    $item = 'smHP' if $random <= 0.4;
	    $item = 'smMP' if $random > 0.4 && $random <= 0.8;
	    $item = 'mdHP' if $random > 0.8 && $random <= 0.9;
	    $item = 'mdMP' if $random > 0.9;
	}
	my ( $drop, $color ) = itemTable( $item, $enemy );
	my $description = getDescription ( $item );
	push @drops, {  drop => $drop,
			color => $color,
			name => $item,
			description => $description,
			quantity => 1 };
    }
    return @drops;
}

sub addInventory {
    #Add item to player inventory
    my ( $item, @inv ) = @_;
    my $column = ($#inv+1) % 5;
    my $row = int(($#inv+1)/5);

    foreach ( @inv ) {
	if ( $_->{name} eq $item->{name} ) {
	    $_->{quantity} += 1;
	    return @inv;
	}
    } 

    $item->{drop}->x( 20+(40-$item->{drop}->w)/2+$column*40 );
    $item->{drop}->y( 50+(40-$item->{drop}->h)/2+$row*40 );
    push @inv, $item;

    return @inv;
}

sub updateInventory {
    #Update player inventory after item is used
    my @inv = @_;
    my $column = 0;
    my $row = 0;

    foreach ( @inv ) {
	if ( $_ ) {
	    $_->{drop}->x( 20+(40-$_->{drop}->w)/2+$column*40 );
	    $_->{drop}->y( 50+(40-$_->{drop}->h)/2+$row*40 );
	    $column++;
	    $row++ if $column % 5 == 0;
	}
    }
    return @inv;
}


sub getItemEffect {
    #Table of item effects
    my $item = shift;

    hpPotion(5) if $item eq 'smHP';
    hpPotion(10) if $item eq 'mdHP';
}

sub getDescription {
    #Table of item descriptions
    my $item = shift;

    return "Small HP Poition: Restores 5 HP" if $item eq 'smHP';
    return "Medium HP Poition: Restores 10 HP" if $item eq 'mdHP';
    return "Small MP Poition: Restores 5 MP" if $item eq 'smMP';
    return "Medium MP Poition: Restores 10 MP" if $item eq 'mdMP';
}

sub hpPotion {
    #HP potion effect
    my $amount = shift;

    if ( $player->{health} + $amount <= calcHealth($player->{level}) ) {
	$player->{health} += $amount;
    } else {
	$player->{health} = calcHealth($player->{level});
    }
}
 
#Render game
sub show {
    #Clear the screen
    $background->blit($app);
    #$app->draw_rect( [0, 0, $app->w, $app->h], 0 );

    #Draw floor
    foreach ( @platforms ) {
	$app->draw_rect( $_, 0x009900FF );
    }

    #Draw player
    $app->draw_rect( $player->{char}, 0xFFFFFFFF );
    $app->draw_rect( $player->{char}, 0xFF0000FF )
	if ( $player->{hitRecovery} && $player->{hitRecovery} % 5 == 0 );

    #Draw bullet
    foreach ( @fire ) {
	$app->draw_rect( $_->{arrow}, 0x663300FF );
    }

    #Draw enemies
    foreach ( @enemies ) {
	$app->draw_rect( $_->{monster}, 0xFFFFFFFF );
    }

    #Draw enemy health bar
    $app->draw_rect( [$app->w-131, 19, 102, 22], [255, 255, 255, 255] ); #White border
    $app->draw_rect( [$app->w-130, 20, 100, 20], [0, 0, 0, 255] ); #Black fill
    $app->draw_rect( SDLx::Rect->new( $app->w-130, 20, ($enemies[$currentEnemy]->{health}/10)*100, 20), 0xFF0000FF )
	if ( defined $currentEnemy && $enemies[$currentEnemy]->{health} > 0 ); #Red fill
    $text->write_xy( $app, $app->w-95, 20, "$enemies[$currentEnemy]->{health} / 10" ) if defined $currentEnemy;

    #Draw player health bar
    $app->draw_rect( [19, 19, 102, 22], [255, 255, 255, 255] ); #White border
    $app->draw_rect( [20, 20, 100, 20], [0, 0, 0, 255] ); #Black fill
    $app->draw_rect( SDLx::Rect->new( 20, 20, ($player->{health}/calcHealth($player->{level}))*100, 20), 0xFF0000FF )
	if $player->{health} > 0; #Red fill
    $text->write_xy( $app, 50, 20, "$player->{health} / " . calcHealth($player->{level}) );

    #Draw exp bar
    $app->draw_rect( [0, $app->h-10, $app->w, 10], [255, 255, 255, 255] ); #White border
    $app->draw_rect( [1, $app->h-9, $app->w-1, 8], [0, 0, 0, 255] ); #Black fill
    $app->draw_rect( SDLx::Rect->new( 1, $app->h-9, ($player->{experience}/expTable($player->{level}))*$app->w, 8), 0xFFFF00FF )
	if $player->{experience} > 0; #Yellow fill
    $text->write_xy( $app, 40, 40, $player->{level} );
    $text->write_xy( $app, 40, 50, $player->{char}->bottom );
    $text->write_xy( $app, 40, 60, $player->{char}->y );

    #Draw items
    foreach ( @items ) {
	$app->draw_rect( $_->{drop}, $_->{color} ); #Draw item
	#$text->write_xy( $app, $_->{drop}->x, $_->{drop}->bottom, $_->{name} ); #Draw item name
    }

    #Draw inventory
    if ( $toggleInventory ) {
	$app->draw_rect( [19, 49, 202, 322], 0xFFFFFFFF );
	$app->draw_rect( [20, 50, 200, 320], 0x000000FF );
	$app->draw_rect( [20+40*$_, 50, 1, 320], 0xFFFFFFFF ) for (1..5);
	$app->draw_rect( [20, 50+40*$_, 200, 1], 0xFFFFFFFF ) for (1..8);
	foreach ( @inventory ) {
	    $app->draw_rect( $_->{drop}, $_->{color} ); #Draw item
	    $text->write_xy( $app, $_->{drop}->right, $_->{drop}->bottom-5, $_->{quantity} ); #Draw quantity
	}
    }

    #Draw death screen
    if ( $player->{health} <= 0 ) {
	$app->draw_rect( [$app->w-350, $app->h-350, 200, 100], 0xFF0000FF );
	    $text->size(24);
	$text->write_xy( $app, 200, 175, "You died!" );
	    $text->size(15);
	$text->write_xy( $app, 190, 200, "Click to respawn..." );
    }

    $app->update();
}

$app->add_event_handler( \&keyboard_event );
$app->add_event_handler( \&mouse_event );
$app->add_show_handler( \&show );

$app->run();
