import { useMemo, useState } from "react"

import { makeBubbleImage, TAIL_WIDTH } from "@/lib/bubble"

/**
 * Строка входящего сообщения по метрикам Telegram-iOS (ChatMessageItemLayoutConstants.compact):
 *   avatar 34×34 (avatarHeaderSize) на x = 7, буква — round bold 16 (avatarPlaceholderFont)
 *   пузырь на x = bubble.edgeInset 3 + avatarInset 38 = 41
 *   text.bubbleInsets = (top 6, left 11, bottom 6, right 11), минимальная высота 35
 *   текст 17pt, цвет incoming primaryTextColor = #000000, фон пузыря fill = #ffffff
 * Все размеры заданы в точках iOS и масштабируются вместе с кадром (var(--pt)).
 */

// AvatarNode.gradientColors — те же пары, что в клиенте
const AVATAR_GRADIENTS: Array<[string, string]> = [
  ["#ff516a", "#ff885e"],
  ["#ffa85c", "#ffcd6a"],
  ["#665fff", "#82b1ff"],
  ["#54cb68", "#a0de7e"],
  ["#4acccd", "#00fcfd"],
  ["#2a9ef1", "#72d5fd"],
  ["#d669ed", "#e0a2f3"],
]

/** Фото для аватарки: public/avatar.jpg. Нет файла — рисуется буква, как в клиенте. */
const AVATAR_IMAGE = "avatar.png"

const BUBBLE_FILL = "#ffffff"
const TEXT_COLOR = "#000000"

// leftInset строки: в клиенте это safe area, здесь — заданный отступ кадра
const ROW_LEFT_INSET = 16
const AVATAR_LEFT = 7 // ChatMessageAvatarHeader.updateLayout: x = leftInset + 7
const AVATAR_SIZE = 34 // avatarHeaderSize() = 34.0
// backgroundFrame.origin.x = bubble.edgeInset 3 + avatarInset 38; в этот кадр входит хвост,
// поэтому тело пузыря сдвинуто ещё на его ширину
const BUBBLE_X = 3 + 38
const BUBBLE_MIN_HEIGHT = 35 // bubble.minimumSize.height
const TEXT_INSET_RIGHT = 11 // text.bubbleInsets.right
const TEXT_INSET_LEFT = 11 - 2 // text.bubbleInsets.left, сдвинут влево по правке
// text.bubbleInsets = top 6 + UIScreenPixel, bottom 6 - UIScreenPixel; на @3x пиксель = 1/3pt
const SCREEN_PIXEL = 1 / 3
const TEXT_INSET_TOP = 6 + SCREEN_PIXEL
const TEXT_INSET_BOTTOM = 6 - SCREEN_PIXEL
const TEXT_SIZE = 17 // Font.regular(17.0)
const TEXT_LINE_HEIGHT = 20.287 // метрика SF Pro Text 17pt: ascent + descent + leading
const TEXT_TRACKING = -0.41 // системный трекинг iOS для 17pt

function gradientIndex(seed: string) {
  let sum = 0
  for (let i = 0; i < seed.length; i++) sum += seed.charCodeAt(i)
  return sum % AVATAR_GRADIENTS.length
}

export function IncomingMessage({ text }: { text: string }) {
  // картинка рисуется сразу в высоту пузыря, поэтому тянется только по ширине
  const bubble = useMemo(() => makeBubbleImage(BUBBLE_FILL, BUBBLE_MIN_HEIGHT), [])
  const [from, to] = AVATAR_GRADIENTS[gradientIndex(text)]
  const letter = text.trim().charAt(0).toUpperCase()
  const [photoFailed, setPhotoFailed] = useState(false)

  return (
    <div
      className="absolute flex items-end"
      style={{
        left: `calc(${ROW_LEFT_INSET} * var(--pt))`,
        bottom: "calc(28 * var(--pt))",
        gap: 0,
      }}
    >
      <div
        className="absolute overflow-hidden rounded-full"
        style={{
          left: `calc(${AVATAR_LEFT} * var(--pt))`,
          bottom: 0,
          width: `calc(${AVATAR_SIZE} * var(--pt))`,
          height: `calc(${AVATAR_SIZE} * var(--pt))`,
          background: `linear-gradient(180deg, ${from}, ${to})`,
        }}
      >
        {photoFailed ? (
          <span
            className="grid size-full place-items-center text-white"
            style={{
              fontFamily: 'ui-rounded, "SF Pro Rounded", system-ui, sans-serif',
              fontWeight: 700,
              fontSize: "calc(16 * var(--pt))",
              lineHeight: 1,
            }}
          >
            {letter}
          </span>
        ) : (
          <img
            src={AVATAR_IMAGE}
            alt=""
            className="size-full object-cover"
            onError={() => setPhotoFailed(true)}
          />
        )}
      </div>

      <div
        className="relative"
        style={{
          marginLeft: `calc(${BUBBLE_X + TAIL_WIDTH} * var(--pt))`,
          minHeight: `calc(${BUBBLE_MIN_HEIGHT} * var(--pt))`,
          paddingLeft: `calc(${TEXT_INSET_LEFT} * var(--pt))`,
          paddingRight: `calc(${TEXT_INSET_RIGHT} * var(--pt))`,
          paddingTop: `calc(${TEXT_INSET_TOP} * var(--pt))`,
          paddingBottom: `calc(${TEXT_INSET_BOTTOM} * var(--pt))`,
          display: "flex",
          alignItems: "flex-start",
        }}
      >
        {/* фон-пузырь: та же растягиваемая картинка, что генерирует клиент */}
        <span
          aria-hidden
          className="pointer-events-none absolute"
          style={{
            top: 0,
            bottom: 0,
            right: 0,
            left: `calc(${-bubble.tailPt} * var(--pt))`,
            borderStyle: "solid",
            borderTopWidth: 0,
            borderBottomWidth: 0,
            borderRightWidth: `calc(${bubble.capPt.right} * var(--pt))`,
            borderLeftWidth: `calc(${bubble.capPt.left} * var(--pt))`,
            borderImageSource: `url(${bubble.url})`,
            borderImageSlice: `0 ${bubble.slice.right} 0 ${bubble.slice.left} fill`,
            borderImageRepeat: "stretch",
          }}
        />
        <span
          className="relative whitespace-nowrap"
          style={{
            color: TEXT_COLOR,
            fontSize: `calc(${TEXT_SIZE} * var(--pt))`,
            lineHeight: `calc(${TEXT_LINE_HEIGHT} * var(--pt))`,
            letterSpacing: `calc(${TEXT_TRACKING} * var(--pt))`,
            fontFamily:
              '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif',
          }}
        >
          {text}
        </span>
      </div>
    </div>
  )
}
