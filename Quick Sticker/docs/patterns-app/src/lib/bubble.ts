/**
 * Пузырь входящего сообщения.
 *
 * Форма хвоста — порт messageBubbleImage из
 * submodules/TelegramPresentationData/Sources/ChatMessageBubbleImages.swift:
 * квадратичные кривые по bottomEllipse с вычитанием topEllipse.
 *
 * Отличие от клиента: правый край скруглён на половину высоты (полукруг),
 * а не на mainRadius 16 — так просили в макете. Картинка рисуется сразу
 * в высоту пузыря и растягивается только по горизонтали (border-image),
 * поэтому вертикальных искажений нет.
 */

// ChatMessageBubbleImages.swift
const MIN_RADIUS_FOR_FULL_TAIL_CORNER = 14.0
export const MAIN_RADIUS = 16.0 // PresentationChatBubbleSettings.default.mainRadius

/** ширина хвоста за пределами тела пузыря (innerSize.width - fixedMainDiameter) */
export const TAIL_WIDTH = 6.0

// bottomEllipse / topEllipse из messageBubbleImage, привязаны к низу пузыря
const BODY_HEIGHT = 33.0
const BOTTOM_ELLIPSE = { x: 24.0, y: 16.0, width: 27.0, height: 17.0 }
const TOP_ELLIPSE = { x: 33.0, y: 14.0, width: 23.0, height: 21.0 }

export type BubbleImage = {
  url: string
  /** срезы в пикселях картинки, для border-image-slice */
  slice: { right: number; left: number }
  /** те же срезы в pt, для border-image-width */
  capPt: { right: number; left: number }
  /** на сколько картинка выступает влево за рамку пузыря */
  tailPt: number
}

/**
 * @param fill        цвет заливки (incoming fill темы)
 * @param height      высота пузыря в pt
 * @param tailRadius  скругление углов со стороны хвоста
 */
export function makeBubbleImage(
  fill: string,
  height: number,
  tailRadius = MAIN_RADIUS,
  scale = 3,
): BubbleImage {
  const roundRadius = height / 2 // полукруг на противоположной хвосту стороне
  const capTail = TAIL_WIDTH + tailRadius // левый cap: хвост и его угол
  const capRound = Math.ceil(roundRadius) // правый cap: полукруглый торец
  const width = capTail + capRound + 1 // +1 — растягиваемая колонка посередине

  const canvas = document.createElement("canvas")
  canvas.width = Math.round(width * scale)
  canvas.height = Math.round(height * scale)
  const ctx = canvas.getContext("2d")!
  ctx.scale(scale, scale)

  // рисуем в ориентации исходящего (хвост справа) и отражаем — как делает клиент
  ctx.translate(width, 0)
  ctx.scale(-1, 1)

  const bodyRight = width - TAIL_WIDTH
  ctx.fillStyle = fill

  // тело: слева полукруг, справа (со стороны хвоста) — углы mainRadius
  ctx.beginPath()
  ctx.moveTo(roundRadius, 0)
  ctx.lineTo(bodyRight - tailRadius, 0)
  ctx.arcTo(bodyRight, 0, bodyRight, tailRadius, tailRadius)
  ctx.lineTo(bodyRight, height - tailRadius)
  ctx.arcTo(bodyRight, height, bodyRight - tailRadius, height, tailRadius)
  ctx.lineTo(roundRadius, height)
  ctx.arcTo(0, height, 0, roundRadius, roundRadius)
  ctx.arcTo(0, 0, roundRadius, 0, roundRadius)
  ctx.closePath()
  ctx.fill()

  // хвост: та же геометрия, что в клиенте, сдвинутая к правому нижнему углу тела
  const dx = bodyRight - BODY_HEIGHT
  const dy = height - BODY_HEIGHT
  const be = {
    x: BOTTOM_ELLIPSE.x + dx,
    y: BOTTOM_ELLIPSE.y + dy,
    width: BOTTOM_ELLIPSE.width,
    height: BOTTOM_ELLIPSE.height,
  }
  const beMidY = be.y + be.height / 2

  if (tailRadius >= MIN_RADIUS_FOR_FULL_TAIL_CORNER) {
    ctx.beginPath()
    ctx.moveTo(be.x, beMidY)
    ctx.quadraticCurveTo(be.x, be.y + be.height, be.x + be.width / 2, be.y + be.height)
    ctx.quadraticCurveTo(be.x + be.width, be.y + be.height, be.x + be.width, beMidY)
    ctx.closePath()
    ctx.fill()
  } else {
    ctx.fillRect(be.x - 2.0, beMidY, be.width + 2.0, be.height / 2)
  }
  ctx.fillRect(
    bodyRight - BODY_HEIGHT / 2,
    Math.floor(dy + BODY_HEIGHT / 2),
    BODY_HEIGHT / 2,
    Math.ceil(beMidY) - Math.floor(dy + BODY_HEIGHT / 2),
  )

  // вырез topEllipse — он и делает хвост изогнутым
  ctx.save()
  ctx.globalCompositeOperation = "destination-out"
  ctx.beginPath()
  ctx.ellipse(
    TOP_ELLIPSE.x + dx + TOP_ELLIPSE.width / 2,
    TOP_ELLIPSE.y + dy + TOP_ELLIPSE.height / 2,
    TOP_ELLIPSE.width / 2,
    TOP_ELLIPSE.height / 2,
    0,
    0,
    Math.PI * 2,
  )
  ctx.fill()
  ctx.restore()

  return {
    url: canvas.toDataURL(),
    slice: { left: capTail * scale, right: capRound * scale },
    capPt: { left: capTail, right: capRound },
    tailPt: TAIL_WIDTH,
  }
}
