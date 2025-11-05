using {/Verse.org/Simulation}
using {/Verse.org/Random}
using {/Fortnite.com/Devices}
using {/Fortnite.com/UI}
using {/Fortnite.com/Characters}
using {/UnrealEngine.com/Temporary/UI}
using {/UnrealEngine.com/Temporary/SpatialMath}


#This section is for code fragments which are necessary for the entire device to work,
#but may not be included with the code base. Normally this is in utils.verse

#If there are errors with SubscribeAgent, uncomment the fragment below

# (Listenable : listenable(agent)).SubscribeAgent(OutputFunc : tuple(agent, t)->void, ExtraData : t where t:type) : cancelable =
# 	    Wrapper := wrapper_agent(t){ExtraData := ExtraData, OutputFunc := OutputFunc}
# 	    Listenable.Subscribe(Wrapper.InputFunc)
	 
# wrapper_agent(t : type) := class():
# 	    ExtraData : t;
# 	    OutputFunc : tuple(agent, t) -> void
# 	    InputFunc(Agent : agent):void = OutputFunc(Agent, ExtraData)


#If there are errors with S2M, uncomment the line below. I have this in my utils file,
#so there is no need for me to write it again, but if you don't have it code won't work

# S2M<localizes>(S: string):message={"{S}"}


#This section of code is responsible for persistence of player data


#This constructor fills not set data with 
MakePlayerCollectTable<constructor>(OldT: player_collect_table)<transacts>:=player_collect_table:
    player_score:= OldT.player_score

#This is a class, responsible for holding player scores, but can be expanded to
#hold other data
player_collect_table:= class<persistable><final>:
    player_score : int = 0

#This variable assigns specific data to specific players, to make sure progression
#is tracked accurately between different playrs
var player_map:weak_map(player, player_collect_table)= map{}


#This functions gets player stats, and handles exceptions which the code may encounter
#If player is inactive, blank table is returned
#If player is active and has a map in player_map, their stats are returned
#If player is active but has no map in player-map, their stats are created and then returned
(Player: player).GetPlayerCollectStats():player_collect_table=
        if(not Player.IsActive[]):
            return player_collect_table{}
        if(PM:= player_map[Player]):
            return PM
        else:
            NewPlayerCollectTable:= player_collect_table{}
            if(set player_map[Player] = NewPlayerCollectTable){}
            return NewPlayerCollectTable


#This section of code is the collectible manager itself, It inhertis from creative device,
#mainly because OnBegin is necessary here, as some events and bindings need to happen
#then.
collectible_manager_device:= class(creative_device):



    #I limited editable values to bare necessities I deemed useful to the user
    #but also necessary for customization of the device
    
    #collectbile_list is used for tracking all collectibles to be controlled by device
    #If you want a collectible to be managed by this device, it needs to be in this list
    @editable
    collectible_list: []collectible_object_device = array{}

    #determines how long it takes for a coin to respawn
    @editable
    respawn_time: float = 10.0

    #determines how much score is awarded for collecting a coin
    @editable
    score_by_coin : int = 10


    #This variable is used for tracking active status of each coin
    var collectible_activity: []logic = array{}


    #This map is used for storing player text blocks, which are used for displaying player
    #scores
    var player_score_texts : [player]text_block = map{}
    
    #This event will be called each time a coin is collected - it includes collecting
    #agent, as well as id of the collected collectible
    coin_collected :event(tuple(agent, int)) = event(tuple(agent, int)){}


    #This function starts at the beginning of the game. Its task here is to load player
    #stats, set up loading stats for joining players, spawning initial coins and
    #converting collect event to more useful event type as well as spawning the
    #core logic of the manager
    OnBegin<override>()<suspends>:void=
        LoadAllPlayersStats()
        PS:= GetPlayspace()
        PS.PlayerAddedEvent().Subscribe(LoadPlayerStats)
        SpawnInitialCoins()
        #This binds each collectibles Collected event to calling coin_collected
        for(id -> collectible: collectible_list):
            #SubscribeAgent is in a wrapper, which allows us to pass additional data
            #Along with the original data that funtion/event already passes
            collectible.CollectedEvent.SubscribeAgent(CallCollect, id)
        spawn:
            AwaitCollection()


    #This adds UI to player. 
    AddScoreUI(Agent: agent):void=
        if:
            Player:= player[Agent]
            Player.IsActive[]
            PlayerUI:= GetPlayerUI[Player]
        then:
            PlayerScoreUI:= MakeScoreCanvas(Agent)
            PlayerUI.AddWidget(PlayerScoreUI)

    #This updates player UI text with provided new score
    UpdatePlayerText(Agent: agent, new_score: int):void=
        if:
            Player:= player[Agent]
            player_score:= player_score_texts[Player]
        then:
            player_score.SetText(S2M("{new_score}"))

    #This loads player stats, gets player agent, and then sets the score
    #from player stats into the score canvas by using score obtained from
    #loaded stats, and agent obained from conversion of player
    LoadPlayerStats(Player: player):void=
        PlayerScore:= Player.GetPlayerCollectStats().player_score
        if:
            Agent:= Player.GetFortCharacter[].GetAgent[]
        then:


            AddScoreUI(Agent)
            UpdatePlayerText(Agent, PlayerScore)


        
    #This executes LoadPlayerStats but for the entire lobby
    LoadAllPlayersStats():void=
        AllPlayers:= GetPlayspace().GetPlayers()
        for(Player: AllPlayers):
            LoadPlayerStats(Player)
    
    #This functions randomly selects 3 unique coin, and reveals them
    #After it does so, it passes the ids of these 3 coins to
    #initialise tracking array of collectible_activity
    SpawnInitialCoins():void=
        var activated_id : []int = array{}
        loop:
            SelID:= GetRandomInt(0, collectible_list.Length - 1)
            if(activated_id.Length = 3):
                break
            if:
                not activated_id.Find[SelID]
                set activated_id += array{SelID}
        for(id: activated_id):
            if(sel_collectible:= collectible_list[id]):
                sel_collectible.Show()
        InitCollectibleActivity(activated_id)    
        

    #This initialises the starting values for collectible_activity, which will serve
    #us to track which coins are active and which are not
    InitCollectibleActivity(ActiveIDS: []int):void=
        set collectible_activity = array{}
        for(id -> collectible: collectible_list):
            var col_status: logic = false
            if(ActiveIDS.Find[id]){set col_status = true}
            set collectible_activity += array{col_status}
            

    #Simple function, which allows us to enhance the base CollectedEvent from collectible
    #and make it so it passes agent and its own id from collectible_list array
    CallCollect(Agent: agent, id: int):void=
        coin_collected.Signal(Agent, id)


    #small function which activates the coin after its been respawned by
    #RespawnRandomInactiveCoin(). The addition of RespawnForAll() is a
    #precaution in case the coin doesnt respawn on Show() on its own
    SetCollectibleActive(ID: int): void=
        if:

            sel_collectible:= collectible_list[ID]
        then:
            sel_collectible.Show()
            sel_collectible.RespawnForAll()


    #small function which hides the coin after its been collected, and sets
    #its activity to false in collectible_activity
    SetCollectibleInactive(ID: int):void=
        if:
            set collectible_activity[ID] = false
            sel_collectible := collectible_list[ID]
        then:
            sel_collectible.Hide()

    
    #This increases score for agent, by using the score_for_coin variable,
    #and saves new_score to persistence,#to make sure the score is saved
    #between sessions. At the end, Player UI is updated with new score
    IncreasePlayerScore(Agent: agent):void=

        if:
            Player:= player[Agent]

        then:
            PlayerStats:= Player.GetPlayerCollectStats()
            current_score:= PlayerStats.player_score
            new_score:= current_score + score_by_coin

            #This is a classic creation of class with a constructor
            #After the ":" we can change value of each variable in
            #constructed class. Each unchanged value will be set to
            #defualt through MakePlayerCollectTable
            new_player_collect_stats:= player_collect_table:
                player_score := new_score
                MakePlayerCollectTable<constructor>(PlayerStats)
            if(set player_map[Player] = new_player_collect_stats ){Print("Correctly set new player save to {new_score}")}
                
            UpdatePlayerText(Agent, new_score)



    #This is the heart of the manager. This loop awaits collection of any coin,
    #and then executes the logic that #follows it. Relatively short amount of
    #code is present before spawn, to make the possibility of two coins being
    #collected in the same execution nigh impossible
    AwaitCollection()<suspends>:void=
        loop:
            collect_tuple:=coin_collected.Await()
            SetCollectibleInactive(collect_tuple(1))
            IncreasePlayerScore(collect_tuple(0))
            #Using spawn here makes sure that multiple coins can respawn at the same time
            spawn:
                RespawnRandomInactiveCoin()




    #This is responsible for coin respawn. It checks which collectibles are inactive,
    #makes an array of their IDs, selects a random one and changes its activity to
    #true, Code is front loaded before respawn time in order to avoid attempts of
    #respawning active coins. The inactive coin gets 'reserved' for respawn and does
    #so after the determined amount of time passes.
    RespawnRandomInactiveCoin()<suspends>:void=
        var inactive_collectibles: []int = array{}
        var selected_collectible : int = -1

        for(id -> collectible : collectible_activity; collectible = false):
            set inactive_collectibles += array{id}
        SelID:= GetRandomInt(0, inactive_collectibles.Length - 1)

        if:
            new_active:= inactive_collectibles[SelID]
            set collectible_activity[new_active] = true
        then:
            set selected_collectible = new_active

        Sleep(respawn_time)
        SetCollectibleActive(selected_collectible)



    #This function creates a canvas, which holds player score interface
    #It also returns said canvas, since it is used to add this UI to player interface
    #Before returning, it sets ScoreText text_block variable to player_score_text map
    #to allow for quick and efficient changes of text
    MakeScoreCanvas(Agent: agent):canvas=

        TitleText:= text_block:
            DefaultText:= S2M("Score: ")
        
        ScoreText:= text_block:
            DefaultText:= S2M("")
        
        ScoreStack:= stack_box:
            Orientation:= orientation.Horizontal
            Slots:= array:
                stack_box_slot:
                    HorizontalAlignment:= horizontal_alignment.Fill
                    VerticalAlignment:= vertical_alignment.Fill
                    Widget:= TitleText
                
                stack_box_slot:
                    HorizontalAlignment:= horizontal_alignment.Fill
                    VerticalAlignment:= vertical_alignment.Fill
                    Widget:= ScoreText

        ScoreCanvas:= canvas:
            Slots:= array:
                canvas_slot:
                    Anchors:= anchors{Minimum:= vector2{X:= 0.5, Y:= 0.0}, Maximum:= vector2{X:= 0.5, Y:= 0.0}}
                    Alignment:= vector2{X:= 0.5, Y:= 0.0}
                    Widget:= ScoreStack
                    SizeToContent:= false

        if:
            Player:= player[Agent]
            set player_score_texts[Player] = ScoreText
        


        return ScoreCanvas