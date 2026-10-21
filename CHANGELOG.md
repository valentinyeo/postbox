# Changelog

## Unreleased

- IGSH-538: Remove WhatsApp Status and stories, including the sidebar, viewer, commands, unread badges and background requests. Chats now start directly below search in both themes.
- IGSH-517: Use saved Windows user API keys instead of stale inherited keys. Voice transcription recovers from a key rotation while the app is running, and failed voice notes try again when their chat is reopened.

- IGSH-526: Add a GitHub-only native desktop verification skill with five feature maps, isolated offline fixture launch, keyboard/UI Automation journeys and screenshot artifacts.
- IGSH-517: Sent voice notes try multilingual recognition when automatic recognition returns no words. Failed transcriptions show a short error below the player instead of an empty space. Microphone dictation still sends each recording only once, and saved transcripts are reused.
