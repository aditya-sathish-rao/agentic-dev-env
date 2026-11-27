# The guest's pi configuration, derived from this machine's personal.nix.
#
# crew-sandbox's guest module ships a DeepSeek-shaped default. This overrides both
# files so the guest's provider and model are the ones the host gateway forwards
# to, instead of a vendor the operator may no longer hold a key for.
#
# The gateway is OpenAI-compatible only (GET /models, POST /chat/completions), so
# the provider is declared with `api = "openai-completions"`. The key is the
# guest's own token file; the real model key never enters the VM.
{ personal, lib, ... }:
let
  gateway = "http://host.lima.internal:3130/model";
in
{
  # mkForce replaces the whole entry, including the module's `source = ./models.json`.
  # home-manager then renders `text` to a store file and points `source` at it.
  home.file.".pi/agent/models.json" = lib.mkForce {
    text = builtins.toJSON {
      "$schema" = "https://pi.dev/schemas/models.schema.json";
      providers.${personal.model.provider} = {
        api = "openai-completions";
        baseUrl = gateway;
        apiKey = "!cat /etc/crew-model-token";
      };
    };
  };

  home.file.".pi/agent/settings.json" = lib.mkForce {
    text = builtins.toJSON {
      "$schema" = "https://pi.dev/schemas/settings.schema.json";
      defaultProvider = personal.model.provider;
      defaultModel = personal.model.name;
      defaultThinkingLevel = personal.model.thinkingLevel;
    };
  };
}
