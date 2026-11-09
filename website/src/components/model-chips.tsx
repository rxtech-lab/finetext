"use client";

import { Chip } from "@mui/material";

export function ModelChips({ labels }: { labels: string[] }) {
  return <div className="model-options">{labels.map((label, i) =>
    <Chip key={label} label={label} variant="outlined" icon={
      <span className="chip-dot" style={{ background: ["#3f7d6e", "#6b739b", "#b4854c", "#6c8fa2"][i] }} />
    } />,
  )}</div>;
}
