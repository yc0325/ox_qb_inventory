export type Slot = {
  slot: number;
  name?: string;
  count?: number;
  weight?: number;
  info?: {
    [key: string]: any;
  };
  quality?: number;
};

export type SlotWithItem = Slot & {
  name: string;
  count: number;
  weight: number;
  quality?: number;
  price?: number;
  currency?: string;
  ingredients?: { [key: string]: number };
  duration?: number;
  image?: string;
  grade?: number | number[];
};
