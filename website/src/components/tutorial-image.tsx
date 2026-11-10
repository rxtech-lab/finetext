"use client";
import Image from "next/image";
import { useState } from "react";
import { Button, Dialog, DialogActions, DialogContent, DialogTitle } from "@mui/material";
import dimensions from "@/lib/tutorial-images.json";
export function TutorialImage({ image, alt, caption, enlarge, close }: { image: keyof typeof dimensions; alt: string; caption: string; enlarge: string; close: string }) {
  const [open, setOpen] = useState(false);
  const size = dimensions[image];
  return <>
    <figure className="tutorial-figure">
      <button className="tutorial-image-button" onClick={() => setOpen(true)} aria-label={enlarge}>
        <Image src={`/tutorials/${image}.webp`} alt={alt} width={size.width} height={size.height} sizes="(max-width: 900px) 90vw, 650px" />
        <span className="tutorial-image-hint">{enlarge} ↗</span>
      </button><figcaption>{caption}</figcaption>
    </figure>
    <Dialog open={open} onClose={() => setOpen(false)} fullWidth maxWidth="lg" aria-labelledby="screenshot-title">
      <DialogTitle id="screenshot-title">{enlarge}</DialogTitle>
      <DialogContent><Image src={`/tutorials/${image}.webp`} alt={alt} width={size.width} height={size.height} sizes="90vw" className="tutorial-zoom" /></DialogContent>
      <DialogActions><Button onClick={() => setOpen(false)}>{close}</Button></DialogActions>
    </Dialog>
  </>;
}
