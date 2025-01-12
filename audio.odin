#+feature dynamic-literals
package ion

import "core:fmt"
import ma "vendor:miniaudio"
import "base:runtime"


Audios :: enum {
	DEAD, BACKGROUND , LADDER, PORTAL, KEY
}

//File names are relative to sounds folder
audio_paths : map[Audios]string = {
	.BACKGROUND = "background.wav",
	.PORTAL     = "portal.wav",
	.LADDER     = "ladder.wav",
	.KEY        = "key.wav",
	.DEAD       = "death.wav",

}

play_audio :: proc(audio : Audios){
	path := fmt.ctprintf("./sounds/%s", audio_paths[audio])
	ctx  := &game.audio_ctx


	if ctx.decoder_at_end[audio]{
		res    := ma.decoder_init_file(path, &ctx.decoder_config, &ctx.decoders[audio])
		if res == .SUCCESS{
			ctx.decoder_at_end[audio] = false
			ctx.playing_count += 1
		}
	}

	/*
	for &decoder, i in &ctx.decoders{
		if ctx.decoder_at_end[i]{
			res    := ma.decoder_init_file(path, &ctx.decoder_config, &decoder)
			if res == .SUCCESS{
				ctx.decoder_at_end[i] = false
				break
			}
		}
	}
	*/
}

AudioConfig :: struct{
	decoders       : [Audios]ma.decoder,
	decoder_config : ma.decoder_config,
	decoder_at_end : [Audios]bool,
	device         : ma.device,
	effects_volume : f32,
	playing_count  : i32,

}

read_and_mix_pcm_frames_f32 :: proc(decoder : ^ma.decoder, pOutputF32 : [^]f32, frame_count: u32) -> u32{
	/*
		The way mixing works is that we just read into a temporary buffer, then take the contents of that buffer 
		and mix it with the contents of the output buffer by simply adding the samples together. You could also clip
		the samples to -1..+1, but I'm not doing that in this example
	*/

	result : ma.result
	temp : [4096]f32
	temp_capin_frames :u32= len(temp)/CHANNEL_COUNT
	total_frames_read :u32= 0

	/* Straigt outta handmade hero */

	for total_frames_read < frame_count{
		frames_read_this_iteration : u64
		total_frames_remaining : u32 = frame_count - total_frames_read

		frames_to_read_this_iteration : u32 = temp_capin_frames
		if frames_to_read_this_iteration > total_frames_remaining{
			frames_to_read_this_iteration = total_frames_remaining
		}

		result = ma.decoder_read_pcm_frames(decoder, &temp, u64(frames_to_read_this_iteration), &frames_read_this_iteration)

		if result != .SUCCESS || frames_read_this_iteration == 0{
			break
		}

		/* Mix the frames together */
		for i_sample in 0..<frames_read_this_iteration * CHANNEL_COUNT{
			pOutputF32[total_frames_read * CHANNEL_COUNT + u32(i_sample)] += (temp[i_sample] * game.audio_ctx.effects_volume)/f32(game.audio_ctx.playing_count)
		}

		total_frames_read += u32(frames_read_this_iteration)
		if frames_read_this_iteration < u64(frames_to_read_this_iteration){
			break; /* Reached EOF */
		}
	}
	return total_frames_read
}


data_callback :: proc "c" (device : ^ma.device, p_output, p_input: rawptr, frame_count : u32){

	context = runtime.default_context()

	ctx          := &game.audio_ctx
	p_output_f32 := cast([^]f32)p_output

	for &decoder, i in &ctx.decoders{
		if !ctx.decoder_at_end[i]{
			frames_read : u32 = read_and_mix_pcm_frames_f32(&decoder, p_output_f32, frame_count)
			if frames_read < frame_count{
				ctx.decoder_at_end[i] = true
				ctx.playing_count -= 1
			}
		}
	}
}

/*
	Initilize miniaudio
*/

SAMPLE_FORMAT :ma.format: .f32
SAMPLE_RATE   :: 48000
CHANNEL_COUNT :: 2



init_miniaudio :: proc(){
	audio_ctx := &game.audio_ctx
	
	using audio_ctx
	audio_ctx.effects_volume = 0.2

	decoder_config = ma.decoder_config_init(SAMPLE_FORMAT, CHANNEL_COUNT, SAMPLE_RATE)

	for &decoder, i in &decoders{
		decoder_at_end[i] = true
	}

	//res    := ma.decoder_init_file("./sounds/background.wav", &decoder_config, &decoders[0])
	play_audio(.BACKGROUND)

	config := ma.device_config_init(.playback)
	config.playback.format   = SAMPLE_FORMAT
	config.playback.channels = CHANNEL_COUNT
	config.sampleRate        = SAMPLE_RATE
	config.dataCallback      = data_callback
	config.pUserData         = nil


	if ma.device_init(nil, &config, &device) != .SUCCESS{
		fmt.println("Failed to open playback device")
		for &decoder in &decoders{
			ma.decoder_uninit(&decoder)
		}
		return
	}

	if ma.device_start(&device) != .SUCCESS{
		fmt.println("Failed to start playback device")
		ma.device_uninit(&device)
		for &decoder in &decoders{
			ma.decoder_uninit(&decoder)
		}
		return
	}

}

























