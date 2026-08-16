import { useEffect } from "react";
import { voiceController } from "../lib/voiceController";

declare global {
  interface Window {
    __todoArmVoice?: () => Promise<void>;
    __todoStartConversation?: () => Promise<void>;
    __todoStopConversation?: () => void;
  }
}

/**
 * Owns the mic session + hotkey hooks.
 * autoListen = Settings “Hey Goku” wake (off by default).
 * ⌘G / Esc / Dictate button work regardless.
 */
export function WakeListener({ autoListen }: { autoListen: boolean }) {
  useEffect(() => {
    voiceController.wakeWordEnabled = autoListen;
    voiceController.enabled = true;

    window.__todoArmVoice = async () => {
      voiceController.enabled = true;
      if (autoListen) await voiceController.arm();
      else await voiceController.startConversation();
    };

    window.__todoStartConversation = async () => {
      await voiceController.startConversation();
    };

    window.__todoStopConversation = () => {
      voiceController.goStandby();
    };

    const offArm = window.todoApi.onArmWake(() => {
      void window.__todoArmVoice?.();
    });

    const offStart = window.todoApi.onStartConversation?.(() => {
      void window.__todoStartConversation?.();
    });

    const offStop = window.todoApi.onStopConversation?.(() => {
      window.__todoStopConversation?.();
    });

    if (autoListen) {
      void voiceController.arm();
    } else if (
      voiceController.getStatus().mode !== "awake" &&
      voiceController.getStatus().mode !== "dictate"
    ) {
      voiceController.stop({ keepMessage: true });
    }

    return () => {
      offArm();
      offStart?.();
      offStop?.();
      delete window.__todoArmVoice;
      delete window.__todoStartConversation;
      delete window.__todoStopConversation;
    };
  }, [autoListen]);

  return null;
}
