#include <sys/types.h>
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdlib.h>
#include <audio.h>

#include "mpg123.h"


/* Analog output constant */
static const char analog_output_res_name[] = ".AnalogOut";


int audio_open(struct audio_info_struct *ai)
{
  int dev = AL_DEFAULT_DEVICE;

  ai->config = ALnewconfig();

  /* Test for correct completion */
  if (ai->config == 0) {
    fprintf(stderr,"audio_open : %d\n",(oserror()));
    exit(-1);
  }
  
  /* Set port parameters */
  if(ai->channels == 2)
    ALsetchannels(ai->config, AL_STEREO);
  else
    ALsetchannels(ai->config, AL_MONO);

  ALsetwidth(ai->config, AL_SAMPLE_16);
  ALsetsampfmt(ai->config,AL_SAMPFMT_TWOSCOMP);
  ALsetqueuesize(ai->config, 131069);

  /* Setup output device to specified module. If there is no module
     specified in ai structure, use the default four output */
  /*
  if ((ai->device) != NULL) {
    
    char *dev_name;
    
    dev_name=malloc((strlen(ai->device) + strlen(analog_output_res_name) + 1) *
                  sizeof(char));
    
    strcpy(dev_name,ai->device);
    strcat(dev_name,analog_output_res_name);
    
    /* Find the asked device resource *
    dev=alGetResourceByName(AL_SYSTEM,dev_name,AL_DEVICE_TYPE);

    /* Free allocated space *
    free(dev_name);

    if (!dev) {
      fprintf(stderr,"Invalid audio resource: %s (%s)\n",dev_name,
            alGetErrorString(oserror()));
      exit(-1);
    }
  }
  */
  
  /* Set the device */
  if (ALsetdevice(ai->config,dev) < 0)
    {
      fprintf(stderr,"audio_open : %d\n",(oserror()));
      exit(-1);
    }
  
  /* Open the audio port */
  ai->port = ALopenport("mpg123-VSC", "w", ai->config);
  if(ai->port == NULL) {
    fprintf(stderr, "Unable to open audio channel: %s\n",
          (oserror()));
    exit(-1);
  }
  
  audio_reset_parameters(ai);
    
  return 1;
}

int audio_reset_parameters(struct audio_info_struct *ai)
{
  int ret;
  ret = audio_set_format(ai);
  if(ret >= 0)
    ret = audio_set_channels(ai);
  if(ret >= 0)
    ret = audio_set_rate(ai);

/* todo: Set new parameters here */

  return ret;
}

int audio_rate_best_match(struct audio_info_struct *ai)
{
  return 0;
}

int audio_set_rate(struct audio_info_struct *ai)
{
  int dev = ALgetdevice(ai->config);
  long params[2];
  
  /* Make sure the device is OK */
  if (dev < 0)
    {
      fprintf(stderr,"audio_set_rate : %d\n",oserror());
      return 1;      
    }

  params[0] = AL_OUTPUT_RATE;
  params[1] = ai->rate;
  
  if (ALsetparams(dev, params, 2) < 0)
    fprintf(stderr,"audio_set_rate : %d\n",oserror());
  
  return 0;
}

int audio_set_channels(struct audio_info_struct *ai)
{
  int ret;
  
  if(ai->channels == 2)
    ret = ALsetchannels(ai->config, AL_STEREO);
  else
    ret = ALsetchannels(ai->config, AL_MONO);

  if (ret < 0)
    fprintf(stderr,"audio_set_channels : %d\n",(oserror()));
  
  return 0;
}

int audio_set_format(struct audio_info_struct *ai)
{
  if (ALsetsampfmt(ai->config,AL_SAMPFMT_TWOSCOMP) < 0)
    fprintf(stderr,"audio_set_format : %d\n",(oserror()));
  
  if (ALsetwidth(ai->config,AL_SAMPLE_16) < 0)
    fprintf(stderr,"audio_set_format : %d\n",(oserror()));
  
  return 0;
}

int audio_get_formats(struct audio_info_struct *ai)
{
  return AUDIO_FORMAT_SIGNED_16;
}


int audio_play_samples(struct audio_info_struct *ai,unsigned char *buf,int len)
{
  if(ai->format == AUDIO_FORMAT_SIGNED_8)
    ALwritesamps(ai->port, buf, len);
  else
    ALwritesamps(ai->port, buf, len>>1);

  return len;
}

int audio_close(struct audio_info_struct *ai)
{
  if (ai->port) {
    while(ALgetfilled(ai->port) > 0)
      sginap(1);  
    ALcloseport(ai->port);
    ALfreeconfig(ai->config);
  }
  
  return 0;
}
