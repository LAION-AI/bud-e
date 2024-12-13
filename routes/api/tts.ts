import { Handlers } from "$fresh/server.ts";
import { Buffer } from "npm:buffer";

const TTS_KEY = Deno.env.get("TTS_KEY") || "";
const TTS_URL = Deno.env.get("TTS_URL") || "";
const TTS_MODEL = Deno.env.get("TTS_MODEL") || "";

async function callMARS6API(
  text: string,
  ttsUrl: string,
  ttsKey: string,
) {
  async function createTTSTask(
    ttsUrl: string,
    ttsKey: string,
    voiceID: number = 20299,
    language: number = 1,
  ) {
    try {
      const response = await fetch(
        `${ttsUrl}/tts`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-api-key": ttsKey,
          },
          body: JSON.stringify({
            text: text,
            voice_id: voiceID,
            language: language,
          }),
        },
      );
      const responseJSON = await response.json();
      console.log(`Status code for creating TTS: ${response.status}`);
      if (response.ok) {
        return responseJSON.task_id;
      } else {
        console.error(
          `Failed to create TTS task for MARS6. Status code: ${response.status}: ${response.statusText}`,
        );
      }
    } catch (error) {
      console.error(`Error in createTTSTask: ${error}`);
    }
  }

  async function pollTTSTask(ttsUrl: string, ttsKey: string, taskID: string) {
    while (true) {
      try {
        const response = await fetch(`${ttsUrl}/tts/${taskID}`, {
          method: "GET",
          headers: {
            "Content-Type": "application/json",
            "x-api-header": ttsKey,
          },
        });

        const responseJSON = await response.json();
        const status = responseJSON.status;
        console.log(`Polling: ${status}`);

        if (status === "SUCCESS") {
          return responseJSON.run_id;
        }
      } catch (error) {
        console.error("Error polling TTS task:", error);
        throw error;
      }

      // Wait for 1.5 seconds before polling again
      await new Promise((resolve) => setTimeout(resolve, 1500));
    }
  }

  async function getTTSAudioResult(
    ttsUrl: string,
    ttsKey: string,
    runID: number,
  ) {
    try {
      const response = await fetch(
        `${ttsUrl}/tts-result/${runID}`,
        {
          method: "GET",
          headers: {
            "x-api-key": ttsKey,
          },
        },
      );
      if (response.ok) {
        return await response.arrayBuffer();
      } else {
        console.error(
          `Failed to fetch TTS audio file from MARS6. Status code: ${response.status}: ${response.statusText}`,
        );
      }
    } catch (error) {
      console.error(`Error in fetching TTS audio file from MARS6: ${error}`);
    }
  }

  try {
    const taskID: string = await createTTSTask(
      ttsUrl,
      ttsKey,
    );
    const runID = await pollTTSTask(ttsKey, ttsKey, taskID);
    return await getTTSAudioResult(ttsUrl, ttsKey, runID);
  } catch (error) {
    console.error(`Failed to call MARS6: ${error}`);
    throw error;
  }
}

async function textToSpeech(
  text: string,
  textPosition: string,
  ttsUrl: string,
  ttsKey: string,
  ttsModel: string,
): Promise<Buffer | null> {
  const boldTextRegex = /\*\*(.*?)\*\*/g;
  text = String(text).replace(boldTextRegex, "$1");

  const buddyRegex = /bud-e/gi;
  text = text.replace(buddyRegex, "buddy");

  console.log("textToSpeech", text);
  console.log("textPosition", textPosition);
  console.log("ttsUrl", ttsUrl);
  console.log("ttsKey", ttsKey);
  console.log("ttsModel", ttsModel);

  const useThisTttsUrl = ttsUrl != '' ? ttsUrl : TTS_URL;
  const useThisTtsKey = ttsKey != '' ? ttsKey : TTS_KEY;
  const useThisTtsModel = ttsModel != '' ? ttsModel : TTS_MODEL;

  try {
    if (ttsModel !== "MARS6") {
      const startTime = Date.now();
      const response = await fetch(useThisTttsUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${useThisTtsKey}`,
        },
        body: JSON.stringify({
          text: text,
          normalize: true,
          format: "mp3",
          reference_id: useThisTtsModel,
          mp3_bitrate: 64,
          opus_bitrate: -1000,
          latency: "normal",
        }),
      });

      if (response.ok) {
        const audioData = await response.arrayBuffer();
        console.log(
          `Audio file received for ${textPosition}, Latency:`,
          Date.now() - startTime,
        );
        return Buffer.from(audioData);
      } else {
        console.error(
          `Failed to synthesize speech. Status code: ${response.status}: ${response.statusText}`,
        );
      }
    } else {
      const audioData = await callMARS6API(
        text,
        ttsUrl,
        ttsKey,
      );
      if (audioData) {
        return Buffer.from(audioData);
      } else {
        console.error(`Failed to synthesize speech.`);
      }
    }
  } catch (error) {
    console.error(`Error in textToSpeech: ${error}`);
  }
  return null;
}

export const handler: Handlers = {
  async POST(req) {
    const { text, textPosition, ttsUrl, ttsKey, ttsModel } = await req.json();
    // console.log("Text:", text);

    if (!text) {
      return new Response("No text provided", { status: 400 });
    }

    const audioData = await textToSpeech(text, textPosition, ttsUrl, ttsKey, ttsModel);

    if (audioData) {
      const response = new Response(audioData, {
        status: 200,
        headers: {
          "Content-Type": "audio/mp3", // Changed from audio/wav to audio/mp3
        },
      });
      return response;
    } else {
      return new Response("Failed to synthesize speech", {
        status: 500,
      });
    }
  },
};
