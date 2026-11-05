import { useEffect, useRef, useState } from "react"

/**
 * Squircle одинаково во всех браузерах.
 *
 * Угол — четверть суперэллипса |x/r|^n + |y/r|^n = 1: при n = 2 это обычная
 * окружность, при n ≈ 4.2 — то же, что рисует Chrome по corner-shape: squircle.
 * Путь строится в пикселях под фактический размер элемента, поэтому углы
 * не растягиваются вместе с кадром, как было бы у SVG-маски.
 *
 * На фичедетект corner-shape не полагаемся: Safari отвечает утвердительно,
 * но не рисует. Форму везде задаёт clip-path, а border-radius при этом обязан
 * быть нулевым — иначе видно пересечение двух обрезок, и круглый угол,
 * который «съедает» больше, перекрывает squircle.
 */

// Показатель подобран по нативному corner-shape: squircle в Chrome —
// замерял границу угла хит-тестом, сошлось на 4.2
const EXPONENT = 4.2
const STEPS = 24 // точек на угол

/** Есть ли clip-path: path(). Если нет — откатываемся на обычный border-radius. */
const supportsPath =
  typeof CSS !== "undefined" &&
  typeof CSS.supports === "function" &&
  CSS.supports("clip-path", 'path("M 0 0 L 1 0 Z")')

export function squirclePath(width: number, height: number, radius: number) {
  const r = Math.min(radius, width / 2, height / 2)
  const points: string[] = []

  // угол задаётся смещением центра и знаками осей
  const corners: Array<[number, number, number, number]> = [
    [r, r, -1, -1], // левый верхний
    [width - r, r, 1, -1], // правый верхний
    [width - r, height - r, 1, 1], // правый нижний
    [r, height - r, -1, 1], // левый нижний
  ]

  corners.forEach(([cx, cy, sx, sy], corner) => {
    // соседние углы обходим в противоположном направлении, иначе контур сам себя срежет
    const reversed = corner % 2 === 1
    for (let i = 0; i <= STEPS; i++) {
      const k = reversed ? STEPS - i : i
      const t = (k / STEPS) * (Math.PI / 2)
      const x = cx + sx * r * Math.cos(t) ** (2 / EXPONENT)
      const y = cy + sy * r * Math.sin(t) ** (2 / EXPONENT)
      points.push(`${points.length === 0 ? "M" : "L"}${x.toFixed(2)} ${y.toFixed(2)}`)
    }
  })

  return `path("${points.join(" ")} Z")`
}

/** Следит за размером элемента и отдаёт clip-path под его текущие размеры. */
export function useSquircle(radius: number) {
  const ref = useRef<HTMLElement | null>(null)
  const [clipPath, setClipPath] = useState<string | undefined>()

  useEffect(() => {
    const el = ref.current
    if (!el) return

    // offsetWidth/Height — размер по вёрстке; getBoundingClientRect у грани,
    // повёрнутой в 3D, вернул бы проекцию, и путь обрезал бы кадр в полоску
    const update = () => {
      const width = el.offsetWidth
      const height = el.offsetHeight
      if (width && height) setClipPath(squirclePath(width, height, radius))
    }
    update()

    const observer = new ResizeObserver(update)
    observer.observe(el)
    return () => observer.disconnect()
  }, [radius])

  return {
    ref,
    clipPath,
    // форму режет clip-path, поэтому своё скругление обнуляем;
    // без поддержки path() остаётся обычный радиус
    borderRadius: supportsPath ? 0 : radius,
  }
}
