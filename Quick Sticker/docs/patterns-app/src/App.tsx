import { useEffect, useMemo, useState } from "react"

import { CylinderCarousel } from "@/components/cylinder-carousel"
import { PatternCard } from "@/components/pattern-card"
import { Button } from "@/components/ui/button"
import { BACKGROUNDS } from "@/lib/backgrounds"
import { averageBrightness, drawMesh } from "@/lib/mesh"
import { loadManifest, type PatternMeta } from "@/lib/patterns"

/** intensity обоев по умолчанию в клиенте */
const INTENSITY = 50
const CARD_MIN_WIDTH = 230

export default function App() {
  const [patterns, setPatterns] = useState<PatternMeta[]>([])
  const [error, setError] = useState<string | null>(null)
  const [bgIndex, setBgIndex] = useState(0)
  const [view, setView] = useState<"grid" | "cylinder">("grid")
  // все фоны считаем один раз: в сетке показываем выбранный, в цилиндре — все по кругу
  const [backgroundUrls, setBackgroundUrls] = useState<string[]>([])

  useEffect(() => {
    loadManifest().then(setPatterns).catch((e: Error) => setError(e.message))
  }, [])

  useEffect(() => {
    const canvas = document.createElement("canvas")
    canvas.width = 130
    canvas.height = 281 // та же пропорция 1125×2436
    const ctx = canvas.getContext("2d")
    if (!ctx) return
    setBackgroundUrls(
      BACKGROUNDS.map((b) => {
        drawMesh(ctx, canvas.width, canvas.height, b.colors, 0)
        return canvas.toDataURL()
      }),
    )
  }, [])

  // тёмный паттерн на светлом фоне и наоборот — порог клиента 0.3
  const patternIsLight = useMemo(
    () => BACKGROUNDS.map((b) => averageBrightness(b.colors) > 0.3),
    [],
  )

  /**
   * Цвета по кругу цилиндра: идут по порядку палитры, но кольцо замкнуто,
   * а 26 граней на 8 цветов не делятся нацело — на стыке цикл наложился бы сам на себя.
   * Поэтому берём следующий по порядку цвет, пропуская те, что уже стоят
   * ближе двух граней (в том числе через стык).
   */
  const cylinderColors = useMemo(() => {
    const palette = BACKGROUNDS.length
    const order: number[] = []
    let next = 0
    for (let i = 0; i < patterns.length; i++) {
      const busy = new Set<number>()
      for (let d = 1; d <= 2; d++) {
        if (order[i - d] !== undefined) busy.add(order[i - d])
        const wrap = i + d - patterns.length
        if (wrap >= 0 && order[wrap] !== undefined) busy.add(order[wrap])
      }
      while (busy.has(next % palette)) next++
      order.push(next % palette)
      next++
    }
    return order
  }, [patterns.length])

  const nextBackground = () => setBgIndex((i) => (i + 1) % BACKGROUNDS.length)

  /** bg — какой фон под кадром: в сетке общий выбранный, в цилиндре свой у каждого */
  const card = (p: PatternMeta, bg: number) => (
    <PatternCard
      key={p.id}
      pattern={p}
      backgroundUrl={backgroundUrls[bg] ?? ""}
      intensity={INTENSITY / 100}
      patternIsLight={patternIsLight[bg]}
      plain={false}
      onNextBackground={nextBackground}
    />
  )

  return (
    <main className="bg-background min-h-svh px-6 py-6">
      {error && (
        <p className="text-destructive text-sm">Не загрузился манифест: {error}</p>
      )}

      <div className="fixed top-4 right-6 z-20 flex gap-1">
        <Button
          size="sm"
          variant={view === "grid" ? "secondary" : "ghost"}
          onClick={() => setView("grid")}
        >
          сетка
        </Button>
        <Button
          size="sm"
          variant={view === "cylinder" ? "secondary" : "ghost"}
          onClick={() => setView("cylinder")}
        >
          цилиндр
        </Button>
      </div>

      {view === "grid" ? (
        <div
          className="mx-auto grid max-w-[1400px] gap-5"
          style={{
            gridTemplateColumns: `repeat(auto-fill, minmax(${CARD_MIN_WIDTH}px, 1fr))`,
          }}
        >
          {patterns.map((p) => card(p, bgIndex))}
        </div>
      ) : (
        patterns.length > 0 && (
          <CylinderCarousel
            count={patterns.length}
            cardWidth={CARD_MIN_WIDTH}
            renderItem={(i) => card(patterns[i], cylinderColors[i])}
          />
        )
      )}
    </main>
  )
}
