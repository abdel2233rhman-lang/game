import { Modal } from '@/components/ui/Modal';

const STEPS = [
  { title: 'اجمع أصحابك', text: 'أنشئ غرفة واحصل على الكود، وشاركه مع أصحابك ليدخلوا من أي جهاز.' },
  { title: 'راهن قبل كل سؤال', text: 'ابدأ برصيد 1000 نقطة، واختر قيمة الرهان قبل أن تظهر الأسئلة.' },
  { title: 'الإجابة الصحيحة تكسبك', text: 'الإجابة الصحيحة تضيف قيمة رهانك، والخاطئة أو المتأخرة تخصمها.' },
  { title: 'سرقة النقاط', text: 'تملك محاولتين لسرقة نقاط خصم بإجابة سؤال خاص، فاختر لحظتك بعناية.' },
  { title: 'الأحداث المفاجئة', text: 'أحداث عشوائية تضاعف النقاط أو تقلب القواعد، فابقَ مستعدًا.' },
];

interface HowToPlayModalProps {
  open: boolean;
  onClose: () => void;
}

export function HowToPlayModal({ open, onClose }: HowToPlayModalProps) {
  return (
    <Modal open={open} title="HOW TO PLAY" onClose={onClose}>
      <ol className="flex flex-col gap-4">
        {STEPS.map((step, index) => (
          <li key={step.title} className="flex gap-4">
            <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full border border-gold-400/50 font-display text-sm font-bold text-gold-300">
              {index + 1}
            </span>
            <div>
              <h3 className="font-bold text-white">{step.title}</h3>
              <p className="mt-1 text-sm leading-[1.5] text-ink-300">{step.text}</p>
            </div>
          </li>
        ))}
      </ol>
    </Modal>
  );
}
