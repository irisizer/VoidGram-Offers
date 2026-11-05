import { useEffect, useRef, useState, type ReactNode } from "react"

/**
 * Раскладка по цилиндру теми же формулами, что в демо jh3yy:
 *   угол на элемент  a = 360° / total
 *   радиус           r = (ширина + зазор) / 2 / tan(a / 2)
 *   каждая грань     rotateY(i * a) translateZ(r)
 * Вращение — своё: непрерывное автовращение, пауза только на время перетаскивания.
 */

type Props = {
  count: number
  cardWidth: number
  /** зазор между гранями, px */
  gap?: number
  /** секунд на полный оборот */
  duration?: number
  renderItem: (index: number) => ReactNode
}

export function CylinderCarousel({
  count,
  cardWidth,
  gap = 20,
  duration = 60,
  renderItem,
}: Props) {
  const [angle, setAngle] = useState(0)
  const dragging = useRef(false)
  const lastX = useRef(0)

  const step = 360 / count
  // пропорция кадра iPhone — кольцу нужна явная высота, иначе центрировать нечего
  const cardHeight = cardWidth * (2436 / 1125)
  // шаг по окружности = ширина грани + зазор, отсюда и радиус
  const radius = (cardWidth + gap) / 2 / Math.tan(Math.PI / count)

  useEffect(() => {
    let raf = 0
    let prev = performance.now()
    const tick = (now: number) => {
      const dt = (now - prev) / 1000
      prev = now
      if (!dragging.current) {
        setAngle((a) => a - (360 / duration) * dt)
      }
      raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf)
  }, [duration])

  return (
    <div
      className="relative w-full overflow-hidden select-none"
      style={{
        height: "calc(100svh - 3rem)",
        // чем ближе перспектива к радиусу, тем сильнее видно, что это цилиндр
        perspective: `${radius * 1.15}px`,
      }}
      onPointerDown={(e) => {
        dragging.current = true
        lastX.current = e.clientX
        ;(e.target as HTMLElement).setPointerCapture?.(e.pointerId)
      }}
      onPointerMove={(e) => {
        if (!dragging.current) return
        const dx = e.clientX - lastX.current
        lastX.current = e.clientX
        setAngle((a) => a + dx * 0.25)
      }}
      onPointerUp={() => {
        dragging.current = false
      }}
      onPointerLeave={() => {
        dragging.current = false
      }}
    >
      <div
        className="absolute top-1/2 left-1/2"
        style={{
          width: `${cardWidth}px`,
          height: `${cardHeight}px`,
          marginLeft: `${-cardWidth / 2}px`,
          marginTop: `${-cardHeight / 2}px`,
          transformStyle: "preserve-3d",
          transform: `translateZ(${-radius}px) rotateY(${angle}deg)`,
        }}
      >
        {Array.from({ length: count }, (_, i) => (
          <div
            key={i}
            className="absolute top-0 left-0 w-full"
            style={{
              transform: `rotateY(${i * step}deg) translateZ(${radius}px)`,
              backfaceVisibility: "hidden",
            }}
          >
            {renderItem(i)}
          </div>
        ))}
      </div>
    </div>
  )
}
