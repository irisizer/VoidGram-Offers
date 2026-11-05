import { useEffect, useState } from "react"

import { IncomingMessage } from "@/components/incoming-message"
import { loadTgv } from "@/lib/mesh"
import { useSquircle } from "@/lib/squircle"
import type { PatternMeta } from "@/lib/patterns"

type Props = {
  pattern: PatternMeta
  backgroundUrl: string
  /** intensity из настроек обоев: >0 — паттерн поверх, <0 — инверсия */
  intensity: number
  /** тёмный паттерн на светлом фоне (brightness > 0.3 у клиента) */
  patternIsLight: boolean
  plain: boolean
  onNextBackground: () => void
}

export function PatternCard({
  pattern,
  backgroundUrl,
  intensity,
  patternIsLight,
  plain,
  onNextBackground,
}: Props) {
  // Safari не знает corner-shape — там форму даёт clip-path
  const squircle = useSquircle(80)
  const [maskUrl, setMaskUrl] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let created: string | null = null
    loadTgv(pattern.file)
      .then((url) => {
        created = url
        setMaskUrl(url)
      })
      .catch((e: Error) => setError(e.message))
    return () => {
      if (created) URL.revokeObjectURL(created)
    }
  }, [pattern.file])

  const mask = maskUrl
    ? {
        maskImage: `url("${maskUrl}")`,
        WebkitMaskImage: `url("${maskUrl}")`,
        maskSize: "100% 100%",
        WebkitMaskSize: "100% 100%",
        maskRepeat: "no-repeat",
        WebkitMaskRepeat: "no-repeat",
      }
    : {}

  const inverted = intensity < 0

  return (
    <figure className="m-0">
      <button
        ref={squircle.ref as React.RefObject<HTMLButtonElement>}
        type="button"
        onClick={onNextBackground}
        className="squircle relative block w-full cursor-pointer overflow-hidden bg-black"
        style={{
          aspectRatio: "1125 / 2436",
          clipPath: squircle.clipPath,
          borderRadius: squircle.borderRadius,
          containerType: "inline-size",
          // 1pt экрана iPhone: ширина 375pt, поэтому 1pt = 100/375 cqw
          ["--pt" as string]: "0.2666667cqw",
        }}
      >
        {/* фон: меш-градиент. В инверсии виден только сквозь фигуры паттерна */}
        {!plain && (
          <img
            src={backgroundUrl}
            alt=""
            className="absolute inset-0 size-full"
            style={{
              opacity: inverted ? Math.abs(intensity) : 1,
              ...(inverted ? mask : {}),
            }}
          />
        )}
        {plain && <div className="absolute inset-0 bg-zinc-100" />}

        {/* сам паттерн: залит чёрным или белым и наложен в softLight */}
        {maskUrl && !inverted && (
          <div
            className="absolute inset-0"
            style={{
              ...mask,
              background: plain ? "#18222d" : patternIsLight ? "#000" : "#fff",
              opacity: plain ? 1 : intensity,
              mixBlendMode: plain ? "normal" : "soft-light",
            }}
          />
        )}

        {maskUrl && <IncomingMessage text={pattern.title} />}

        {!maskUrl && (
          <span className="absolute inset-0 grid place-items-center text-xs text-white/50">
            {error ?? "…"}
          </span>
        )}
      </button>
    </figure>
  )
}
