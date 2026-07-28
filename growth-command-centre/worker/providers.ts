import type { ChannelId, ProviderCapability, ProviderConnection } from "../shared/types";

export interface ProviderDefinition {
  id: ChannelId | "posthog" | "slack" | "media";
  label: string;
  capabilities: ProviderCapability[];
  accessNote: string;
}

export interface ChannelProvider {
  readonly definition: ProviderDefinition;
  canExecute(connection: ProviderConnection | undefined, capability: ProviderCapability): { ok: boolean; reason?: string };
}

class DeclaredCapabilityProvider implements ChannelProvider {
  constructor(readonly definition: ProviderDefinition) {}

  canExecute(connection: ProviderConnection | undefined, capability: ProviderCapability): { ok: boolean; reason?: string } {
    if (!connection || connection.status !== "connected") {
      return { ok: false, reason: `${this.definition.label} is not connected.` };
    }
    if (!connection.capabilities.includes(capability)) {
      return { ok: false, reason: `${this.definition.label} has not been authorized for ${capability}.` };
    }
    return { ok: true };
  }
}

const providerDefinitions: ProviderDefinition[] = [
  {
    id: "posthog",
    label: "PostHog",
    capabilities: ["read_analytics", "resolve_audience", "create_product_experiment"],
    accessNote: "Read-only analytics is default; product experiment writes use a separately scoped admin connection."
  },
  {
    id: "resend",
    label: "Resend",
    capabilities: ["send_email", "read_channel_metrics"],
    accessNote: "Only approved, consented cohorts can be resolved into recipient addresses at send time."
  },
  {
    id: "linkedin",
    label: "LinkedIn",
    capabilities: ["publish_organic", "create_campaign", "read_channel_metrics"],
    accessNote: "Organization posting and advertising remain unavailable until LinkedIn grants the required product access."
  },
  {
    id: "meta",
    label: "Meta / Instagram",
    capabilities: ["publish_organic", "create_campaign", "read_channel_metrics"],
    accessNote: "Requires a connected business portfolio, the selected accounts, and approved app permissions."
  },
  {
    id: "tiktok",
    label: "TikTok",
    capabilities: ["publish_organic", "create_campaign", "read_channel_metrics"],
    accessNote: "Marketing and organic access are connected and approved separately."
  },
  {
    id: "snapchat",
    label: "Snapchat",
    capabilities: ["publish_organic", "create_campaign", "read_channel_metrics"],
    accessNote: "Marketing API OAuth is required; public-profile publishing can require allow-list access."
  },
  {
    id: "google_ads",
    label: "Google Ads",
    capabilities: ["create_campaign", "read_channel_metrics"],
    accessNote: "Requires a linked manager account, OAuth, and a selected customer account."
  },
  {
    id: "x",
    label: "X",
    capabilities: ["publish_organic", "create_campaign", "read_channel_metrics"],
    accessNote: "Availability follows the connected X API plan and account permissions."
  },
  {
    id: "reddit",
    label: "Reddit",
    capabilities: ["publish_organic", "create_campaign", "read_channel_metrics"],
    accessNote: "Advertising and community actions are capability-gated per connected account."
  },
  {
    id: "pinterest",
    label: "Pinterest",
    capabilities: ["publish_organic", "create_campaign", "read_channel_metrics"],
    accessNote: "Requires a business account and approved app connection."
  },
  {
    id: "slack",
    label: "Slack",
    capabilities: [],
    accessNote: "Slack is the primary approval surface; signed actions are verified server-side."
  },
  {
    id: "media",
    label: "AI media gateway",
    capabilities: ["generate_image", "generate_video"],
    accessNote: "Admins connect their own image and video providers; generated assets always wait for approval."
  }
];

export const providers = new Map(providerDefinitions.map((definition) => [definition.id, new DeclaredCapabilityProvider(definition)]));

export function providerDefinition(id: ProviderDefinition["id"]): ProviderDefinition {
  const provider = providers.get(id);
  if (!provider) throw new Error(`Unknown provider: ${id}`);
  return provider.definition;
}

export function knownProviderDefinitions(): ProviderDefinition[] {
  return providerDefinitions;
}
