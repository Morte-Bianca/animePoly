export default function Board() {
  const tiles = Array.from({ length: 40 }, (_, i) => i);
  return (
    <div className="grid grid-cols-8 gap-1">
      {tiles.map((i) => (
        <div
          key={i}
          className="h-10 w-10 bg-white border flex items-center justify-center text-xs"
        >
          {i}
        </div>
      ))}
    </div>
  );
}
